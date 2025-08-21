// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {Tick} from './TickStorage.sol';

import {AuctionParameters, IAuction} from './interfaces/IAuction.sol';

import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';

import {CheckpointLib} from './libraries/CheckpointLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is BidStorage, CheckpointStorage, AuctionStepStorage, PermitSingleForwarder, IAuction {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using BidLib for Bid;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using DemandLib for Demand;
    using SafeCastLib for uint256;

    /// @notice The currency of the auction
    Currency public immutable currency;
    /// @notice The token of the auction
    IERC20Minimal public immutable token;
    /// @notice The total supply of token to sell
    uint256 public immutable totalSupply;
    /// @notice The recipient of any unsold tokens
    address public immutable tokensRecipient;
    /// @notice The recipient of the funds from the auction
    address public immutable fundsRecipient;
    /// @notice The block at which purchased tokens can be claimed
    uint64 public immutable claimBlock;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;

    /// @notice The sum of demand in ticks above the clearing price
    Demand public sumDemandAboveClearing;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        CheckpointStorage(_parameters.floorPrice, _parameters.tickSpacing)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        currency = Currency.wrap(_parameters.currency);
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        tokensRecipient = _parameters.tokensRecipient;
        fundsRecipient = _parameters.fundsRecipient;
        claimBlock = _parameters.claimBlock;
        validationHook = IValidationHook(_parameters.validationHook);

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (floorPrice == 0) revert FloorPriceIsZero();
        if (tickSpacing == 0) revert TickSpacingIsZero();
        if (claimBlock < endBlock) revert ClaimBlockIsBeforeEndBlock();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived(address _token, uint256 _amount) external view {
        if (_token != address(token)) revert IDistributionContract__InvalidToken();
        if (_amount != totalSupply) revert IDistributionContract__InvalidAmount();
        if (token.balanceOf(address(this)) != _amount) revert IDistributionContract__InvalidAmountReceived();
    }

    /// @notice Advance the current step until the current block is within the step
    function _advanceToCurrentStep() internal returns (Checkpoint memory _checkpoint, uint256 _checkpointedBlock) {
        // Advance the current step until the current block is within the step
        _checkpoint = latestCheckpoint();
        _checkpointedBlock = lastCheckpointedBlock;
        uint256 end = step.endBlock;

        while (block.number >= end && end != endBlock) {
            if (_checkpoint.clearingPrice > 0) {
                _checkpoint = _checkpoint.transform(_checkpointedBlock, end - _checkpointedBlock, step.mps);
            }
            _checkpointedBlock = end;
            _advanceStep();
            end = step.endBlock;
        }
    }

    /// @notice Calculate the new clearing price, given:
    /// @param _tickUpperPrice The price of the tick at which there is not enough demand to fill the block supply
    /// @param minimumClearingPrice The minimum clearing price
    /// @param blockTokenSupply The token supply at or above tickUpperPrice in the block
    /// @param cumulativeMps The cumulative mps at the last checkpoint
    function _calculateNewClearingPrice(
        uint256 _tickUpperPrice,
        uint256 minimumClearingPrice,
        uint256 blockTokenSupply,
        uint24 cumulativeMps
    ) internal view returns (uint256) {
        uint256 resolvedBlockDemandAboveClearing = sumDemandAboveClearing.resolve(_tickUpperPrice).applyMpsDenominator(
            step.mps, AuctionStepLib.MPS - cumulativeMps
        );
        // If there is no demand above the clearing price or the demand is equal to the block supply, the clearing price is tickUpper
        // This can happen in a few scenarios:
        // 1. The auction just started and the tickUpper represents the floor price and should be returned
        // 2. There is fully matching demand at tickUpper, so it should be new clearing price
        // 3. There is no demand above the current clearing price, so TickUpper is the highest tick in the book and should be new clearing price
        if (resolvedBlockDemandAboveClearing == 0 || resolvedBlockDemandAboveClearing >= blockTokenSupply) {
            return _tickUpperPrice;
        }

        Demand memory blockSumDemandAboveClearing =
            sumDemandAboveClearing.applyMpsDenominator(step.mps, AuctionStepLib.MPS - cumulativeMps);
        uint256 _clearingPrice =
            blockSumDemandAboveClearing.currencyDemand / (blockTokenSupply - blockSumDemandAboveClearing.tokenDemand);

        if (_clearingPrice < minimumClearingPrice) {
            return minimumClearingPrice;
        }
        // If the new clearing price is below the floor price, set it to the floor price
        if (_clearingPrice < floorPrice) {
            return floorPrice;
        }
        // Round down to the nearest tick boundary
        _clearingPrice = (_clearingPrice - (_clearingPrice % tickSpacing));
        return _clearingPrice;
    }

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() public returns (Checkpoint memory _checkpoint) {
        if (block.number < startBlock) revert AuctionNotStarted();

        // Advance to the current step if needed, summing up the results since the last checkpointed block
        (_checkpoint,) = _advanceToCurrentStep();

        uint256 blockTokenSupply = (totalSupply - _checkpoint.totalCleared).fullMulDiv(
            step.mps, AuctionStepLib.MPS - _checkpoint.cumulativeMps
        );

        // All active demand above the current clearing price
        Demand memory _sumDemandAboveClearing = sumDemandAboveClearing;
        uint256 minimumClearingPrice = _checkpoint.clearingPrice;
        Tick memory _tickUpper = getTick(tickUpperPrice);
        // Resolve the demand at the next initialized tick
        // Find the tick which does not fully match the supply, or the highest tick in the book
        while (
            _sumDemandAboveClearing.resolve(tickUpperPrice).applyMpsDenominator(
                step.mps, AuctionStepLib.MPS - _checkpoint.cumulativeMps
            ) >= blockTokenSupply
        ) {
            // Subtract the demand at the current tickUpper before advancing to the next tick
            _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_tickUpper.demand);
            // If there is no future tick, break to avoid ending up in a bad state
            if (_tickUpper.next == MAX_TICK_ID) {
                break;
            }
            // Since there was enough demand at tick upper to fill the supply, the new clearing price must be >= tickUpperPrice
            minimumClearingPrice = tickUpperPrice;
            tickUpperPrice = toPrice(_tickUpper.next);
            _tickUpper = getTick(tickUpperPrice);
        }

        sumDemandAboveClearing = _sumDemandAboveClearing;

        uint256 newClearingPrice = _calculateNewClearingPrice(
            tickUpperPrice, minimumClearingPrice, blockTokenSupply, _checkpoint.cumulativeMps
        );

        _checkpoint = _updateCheckpoint(_checkpoint, step, _sumDemandAboveClearing, newClearingPrice, blockTokenSupply);

        _insertCheckpoint(_checkpoint);

        emit CheckpointUpdated(
            block.number, _checkpoint.clearingPrice, _checkpoint.totalCleared, _checkpoint.cumulativeMps
        );
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory _checkpoint) {
        uint256 _checkpointedBlock;
        (_checkpoint, _checkpointedBlock) = _advanceToCurrentStep();
        if (endBlock - _checkpointedBlock > 0) {
            _checkpoint = _checkpoint.transform(_checkpointedBlock, endBlock - _checkpointedBlock, step.mps);
        }
        return _checkpoint;
    }

    function _submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevTickId,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        // First bid in a block updates the clearing price
        if (lastCheckpointedBlock != block.number) checkpoint();

        _initializeTickIfNeeded(prevTickId, maxPrice);

        if (address(validationHook) != address(0)) {
            validationHook.validate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        }
        uint256 _clearingPrice = clearingPrice();
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        BidLib.validate(maxPrice, _clearingPrice, tickSpacing);

        _updateTick(toId(maxPrice), exactIn, amount);

        bidId = _createBid(exactIn, amount, owner, maxPrice);

        if (exactIn) {
            sumDemandAboveClearing = sumDemandAboveClearing.addCurrencyAmount(amount);
        } else {
            sumDemandAboveClearing = sumDemandAboveClearing.addTokenAmount(amount);
        }

        emit BidSubmitted(bidId, owner, maxPrice, exactIn, amount);
    }

    /// @inheritdoc IAuction
    function submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) external payable returns (uint256) {
        if (block.number >= endBlock) revert AuctionIsOver();
        uint256 resolvedAmount = exactIn ? amount : amount * maxPrice;
        if (resolvedAmount == 0) revert InvalidAmount();
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        return _submitBid(maxPrice, exactIn, amount, owner, prevHintId, hookData);
    }

    /// @notice Given a bid, tokens filled and refund, process the transfers and refund
    function _processExit(uint256 bidId, Bid memory bid, uint256 tokensFilled, uint256 refund) internal {
        address _owner = bid.owner;

        if (tokensFilled == 0) {
            _deleteBid(bidId);
        } else {
            bid.tokensFilled = tokensFilled;
            bid.exitedBlock = uint64(block.number);
            _updateBid(bidId, bid);
        }

        if (refund > 0) {
            currency.transfer(_owner, refund);
        }

        emit BidExited(bidId, _owner);
    }

    /// @inheritdoc IAuction
    function exitBid(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        if (block.number < endBlock || bid.maxPrice <= clearingPrice()) revert CannotExitBid();

        /// @dev Bid was fully filled and the auction is now over
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        (uint256 tokensFilled, uint256 currencySpent) =
            _accountFullyFilledCheckpoints(_getFinalCheckpoint(), startCheckpoint, bid);

        uint256 resolvedAmount = bid.exactIn ? bid.amount : bid.amount * bid.maxPrice;
        _processExit(bidId, bid, tokensFilled, resolvedAmount - currencySpent);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint256 outbidCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        // Outbid checkpoint is the first checkpoint where the clearing price is strictly > bid.maxPrice
        Checkpoint memory outbidCheckpoint = _getCheckpoint(outbidCheckpointBlock);
        // Last valid checkpoint is the last checkpoint where the clearing price is <= bid.maxPrice
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(outbidCheckpoint.prev);

        uint256 tokensFilled;
        uint256 currencySpent;
        uint256 _clearingPrice = clearingPrice();
        /// @dev Bid has been outbid
        if (bid.maxPrice < _clearingPrice) {
            if (outbidCheckpoint.clearingPrice <= bid.maxPrice) revert InvalidCheckpointHint();

            uint256 nextCheckpointBlock;
            (tokensFilled, currencySpent, nextCheckpointBlock) =
                _accountPartiallyFilledCheckpoints(outbidCheckpoint, bid);
            /// Now account for the fully filled checkpoints until the startCheckpoint
            (uint256 _tokensFilled, uint256 _currencySpent) =
                _accountFullyFilledCheckpoints(_getCheckpoint(nextCheckpointBlock), startCheckpoint, bid);
            tokensFilled += _tokensFilled;
            currencySpent += _currencySpent;
        } else if (block.number >= endBlock && bid.maxPrice == _clearingPrice) {
            /// @dev Bid is partially filled at the end of the auction
            /// Setup:
            /// lastValidCheckpoint --- ... | outbidCheckpoint --- ... | latestCheckpoint ... | endBlock
            /// price < clearingPrice       | clearingPrice == price -------------------------->
            if (outbidCheckpoint.clearingPrice < bid.maxPrice || lastValidCheckpoint.clearingPrice > bid.maxPrice) {
                revert InvalidCheckpointHint();
            }

            (tokensFilled, currencySpent) = _accountFullyFilledCheckpoints(lastValidCheckpoint, startCheckpoint, bid);
            (uint256 partialTokensFilled, uint256 partialCurrencySpent,) =
                _accountPartiallyFilledCheckpoints(_getFinalCheckpoint(), bid);
            tokensFilled += partialTokensFilled;
            currencySpent += partialCurrencySpent;
        } else {
            revert CannotExitBid();
        }

        uint256 resolvedAmount = bid.exactIn ? bid.amount : bid.amount * bid.maxPrice;
        _processExit(bidId, bid, tokensFilled, resolvedAmount - currencySpent);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock == 0) revert BidNotExited();
        if (block.number < claimBlock) revert NotClaimable();

        uint256 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        token.transfer(bid.owner, tokensFilled);

        emit TokensClaimed(bid.owner, tokensFilled);
    }

    receive() external payable {}
}
