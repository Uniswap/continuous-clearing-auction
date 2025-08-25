// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {AuctionParameters, IAuction} from './interfaces/IAuction.sol';

import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';

import {CheckpointLib} from './libraries/CheckpointLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is BidStorage, CheckpointStorage, AuctionStepStorage, TickStorage, PermitSingleForwarder, IAuction {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using BidLib for Bid;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using DemandLib for Demand;
    using SafeCastLib for uint256;

    /// @notice Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
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

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
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
    /// @dev The checkpoint must be up to date since `transform` depends on the clearingPrice
    function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint256 blockNumber)
        internal
        returns (Checkpoint memory)
    {
        // Advance the current step until the current block is within the step
        // Start at the smaller of the last checkpointed block or the start block of the current step
        uint256 start = step.startBlock > lastCheckpointedBlock ? lastCheckpointedBlock : step.startBlock;
        uint256 end = step.endBlock;

        while (blockNumber > end) {
            _checkpoint = _checkpoint.transform(end - 1 - start, step.mps);
            start = end;
            if (end == endBlock) break;
            _advanceStep();
            end = step.endBlock;
        }
        return _checkpoint;
    }

    /// @notice Calculate the new clearing price
    /// @param minimumClearingPrice The minimum clearing price
    /// @param supply The token supply at or above nextActiveTickPrice in the block
    function _calculateNewClearingPrice(uint256 minimumClearingPrice, uint256 supply) internal view returns (uint256) {
        // Get the demand at and above `minimumClearingPrice` being sold
        Demand memory blockSumDemandAboveClearing = sumDemandAboveClearing.applyMps(step.mps);

        // Calculate the clearing price by first subtracting the exactOut tokenDemand then dividing by the currencyDemand
        // Follows the formula ~ ETH / tokens = price
        uint256 _clearingPrice = blockSumDemandAboveClearing.currencyDemand.fullMulDiv(
            FixedPoint96.Q96, (supply - blockSumDemandAboveClearing.tokenDemand)
        );

        // If the new clearing price is below the minimum clearing price return the minimum clearing price
        if (_clearingPrice < minimumClearingPrice) return minimumClearingPrice;
        // If the new clearing price is below the floor price return the floor price
        if (_clearingPrice < floorPrice) return floorPrice;
        // Otherwise, round down to the nearest tick boundary
        return (_clearingPrice - (_clearingPrice % tickSpacing));
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @param blockNumber The block number to checkpoint at
    function _unsafeCheckpoint(uint256 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        _checkpoint = latestCheckpoint();
        if (blockNumber == lastCheckpointedBlock) return _checkpoint;
        if (blockNumber < startBlock) revert AuctionNotStarted();
        if (blockNumber > endBlock) revert AuctionIsOver();

        // Get the supply being sold in this block, accounting for rollovers of past supply
        uint256 supply =
            ((totalSupply - _checkpoint.totalCleared) * step.mps) / (AuctionStepLib.MPS - _checkpoint.cumulativeMps);

        // All active demand above the current clearing price
        Demand memory _sumDemandAboveClearing = sumDemandAboveClearing;
        // The minimum clearing price
        uint256 minimumClearingPrice = _checkpoint.clearingPrice;
        Tick memory _nextActiveTick = getTick(nextActiveTickPrice);

        // Find the tick where the demand at and above it is NOT enough to fill the supply
        // Sets nextActiveTickPrice to MAX_TICK_PRICE if the highest tick in the book is reached
        while (_sumDemandAboveClearing.resolve(nextActiveTickPrice).applyMps(step.mps) >= supply) {
            // Subtract the demand at nextActiveTick
            _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_nextActiveTick.demand);
            // The nextActiveTickPrice is now the minimum clearing price because there was enough demand to fill the supply
            minimumClearingPrice = nextActiveTickPrice;
            // Advance to the next tick
            uint256 _nextTickPrice = _nextActiveTick.next;
            nextActiveTickPrice = _nextTickPrice;
            _nextActiveTick = getTick(_nextTickPrice);
        }

        // Save state variables
        sumDemandAboveClearing = _sumDemandAboveClearing;

        _checkpoint.clearingPrice = _calculateNewClearingPrice(minimumClearingPrice, supply);
        uint256 resolvedDemandAboveClearing = _sumDemandAboveClearing.resolve(_checkpoint.clearingPrice);

        // If the clearing price is the floor price, we can only clear the current demand at the floor price
        if (_checkpoint.clearingPrice == floorPrice) {
            // We can only clear the current demand at the floor price
            _checkpoint.blockCleared = resolvedDemandAboveClearing.applyMps(step.mps);
        }
        // Otherwise, we can clear the entire supply being sold in the block
        else {
            _checkpoint.blockCleared = supply;
        }

        // The local checkpoint is now up to date. Advance it to the current block
        _checkpoint = _advanceToCurrentStep(_checkpoint, blockNumber);

        // Account for any time in between this checkpoint and the greater of the start of the step or the last checkpointed block
        uint256 blockDelta =
            blockNumber - (step.startBlock > lastCheckpointedBlock ? step.startBlock : lastCheckpointedBlock);
        uint24 mpsSinceLastCheckpoint = (step.mps * blockDelta).toUint24();

        _checkpoint.totalCleared += _checkpoint.blockCleared * blockDelta;
        _checkpoint.cumulativeMps += mpsSinceLastCheckpoint;
        _checkpoint.cumulativeMpsPerPrice +=
            CheckpointLib.getMpsPerPrice(mpsSinceLastCheckpoint, _checkpoint.clearingPrice);
        _checkpoint.resolvedDemandAboveClearingPrice = resolvedDemandAboveClearing;
        _checkpoint.mps = step.mps;
        _checkpoint.prev = lastCheckpointedBlock;
        _insertCheckpoint(_checkpoint, blockNumber);

        emit CheckpointUpdated(
            blockNumber, _checkpoint.clearingPrice, _checkpoint.totalCleared, _checkpoint.cumulativeMps
        );
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory _checkpoint) {
        return _unsafeCheckpoint(endBlock);
    }

    function _submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        checkpoint();

        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        if (address(validationHook) != address(0)) {
            validationHook.validate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        }
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        if (maxPrice <= clearingPrice()) revert InvalidBidPrice();

        _updateTick(maxPrice, exactIn, amount);

        bidId = _createBid(exactIn, amount, owner, maxPrice);

        if (exactIn) {
            sumDemandAboveClearing = sumDemandAboveClearing.addCurrencyAmount(amount);
        } else {
            sumDemandAboveClearing = sumDemandAboveClearing.addTokenAmount(amount);
        }

        emit BidSubmitted(bidId, owner, maxPrice, exactIn, amount);
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
    function checkpoint() public returns (Checkpoint memory _checkpoint) {
        return _unsafeCheckpoint(block.number);
    }

    /// @inheritdoc IAuction
    function submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable returns (uint256) {
        if (block.number >= endBlock) revert AuctionIsOver();
        uint256 requiredCurrencyAmount = BidLib.inputAmount(exactIn, amount, maxPrice);
        if (requiredCurrencyAmount == 0) revert InvalidAmount();
        if (currency.isAddressZero()) {
            if (msg.value != requiredCurrencyAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(
                Currency.unwrap(currency), msg.sender, address(this), requiredCurrencyAmount
            );
        }
        return _submitBid(maxPrice, exactIn, amount, owner, prevTickPrice, hookData);
    }

    /// @inheritdoc IAuction
    function exitBid(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        Checkpoint memory finalCheckpoint = _unsafeCheckpoint(endBlock);

        if (block.number < endBlock || bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();
        /// @dev Bid was fully filled and the auction is now over
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        (uint256 tokensFilled, uint256 currencySpent) =
            _accountFullyFilledCheckpoints(finalCheckpoint, startCheckpoint, bid);

        _processExit(bidId, bid, tokensFilled, bid.inputAmount() - currencySpent);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint256 outbidCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        Checkpoint memory finalCheckpoint = _unsafeCheckpoint(endBlock);
        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        // Outbid checkpoint is the first checkpoint where the clearing price is strictly > bid.maxPrice
        Checkpoint memory outbidCheckpoint = _getCheckpoint(outbidCheckpointBlock);
        // Last valid checkpoint is the last checkpoint where the clearing price is <= bid.maxPrice
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(outbidCheckpoint.prev);

        /// @dev Bid is partially filled. Require the outbid checkpoint to be strictly > bid.maxPrice and the last valid checkpoint to be <= bid.maxPrice
        /// lastValidCheckpoint --- ... | outbidCheckpoint --- ... | latestCheckpoint ... | endBlock
        /// price == clearingPrice      | clearingPrice > price -------------------------->
        if (outbidCheckpoint.clearingPrice < bid.maxPrice || lastValidCheckpoint.clearingPrice > bid.maxPrice) {
            revert InvalidCheckpointHint();
        }

        uint256 tokensFilled;
        uint256 currencySpent;
        /// @dev Bid has been outbid
        if (bid.maxPrice < finalCheckpoint.clearingPrice) {
            uint256 nextCheckpointBlock;
            (tokensFilled, currencySpent, nextCheckpointBlock) = _accountPartiallyFilledCheckpoints(
                lastValidCheckpoint, bid.demand(), getTick(bid.maxPrice).demand.resolve(bid.maxPrice), bid.maxPrice
            );
            /// Now account for the fully filled checkpoints until the startCheckpoint
            (uint256 _tokensFilled, uint256 _currencySpent) =
                _accountFullyFilledCheckpoints(_getCheckpoint(nextCheckpointBlock), startCheckpoint, bid);
            tokensFilled += _tokensFilled;
            currencySpent += _currencySpent;
        } else if (block.number >= endBlock && bid.maxPrice == finalCheckpoint.clearingPrice) {
            (tokensFilled, currencySpent) = _accountFullyFilledCheckpoints(lastValidCheckpoint, startCheckpoint, bid);
            (uint256 partialTokensFilled, uint256 partialCurrencySpent,) = _accountPartiallyFilledCheckpoints(
                finalCheckpoint, bid.demand(), getTick(bid.maxPrice).demand.resolve(bid.maxPrice), bid.maxPrice
            );
            tokensFilled += partialTokensFilled;
            currencySpent += partialCurrencySpent;
        } else {
            revert CannotExitBid();
        }

        _processExit(bidId, bid, tokensFilled, bid.inputAmount() - currencySpent);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock == 0) revert BidNotExited();
        if (block.number < claimBlock) revert NotClaimable();

        uint256 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        Currency.wrap(address(token)).transfer(bid.owner, tokensFilled);

        emit TokensClaimed(bid.owner, tokensFilled);
    }
}
