// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {TickStorage} from './TickStorage.sol';

import {console2} from 'forge-std/console2.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

import {AuctionParameters, IAuction} from './interfaces/IAuction.sol';
import {Tick, TickLib} from './libraries/TickLib.sol';

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
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is PermitSingleForwarder, IAuction, TickStorage, AuctionStepStorage, BidStorage, CheckpointStorage {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using TickLib for Tick;
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
    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;
    /// @notice The starting price of the auction
    uint256 public immutable floorPrice;

    /// @notice The sum of demand in ticks above the clearing price
    Demand public sumDemandAboveClearing;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        currency = Currency.wrap(_parameters.currency);
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        tokensRecipient = _parameters.tokensRecipient;
        fundsRecipient = _parameters.fundsRecipient;
        claimBlock = _parameters.claimBlock;
        tickSpacing = _parameters.tickSpacing;
        validationHook = IValidationHook(_parameters.validationHook);
        floorPrice = _parameters.floorPrice;

        // Initialize a tick for the floor price
        _initializeTickIfNeeded(0, floorPrice);

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

    function clearingPrice() public view returns (uint256) {
        return latestCheckpoint().clearingPrice;
    }

    /// @notice Advance the current step until the current block is within the step
    function _advanceToCurrentStep() internal returns (Checkpoint memory _checkpoint) {
        // Advance the current step until the current block is within the step
        _checkpoint = latestCheckpoint();
        uint256 start = lastCheckpointedBlock;
        uint256 end = step.endBlock;

        while (block.number >= end) {
            if (_checkpoint.clearingPrice > 0) {
                _checkpoint = _checkpoint.transform(start, end - start, step.mps);
            }
            start = end;
            _advanceStep();
            end = step.endBlock;
        }
    }

    /// @notice Calculate the new clearing price
    function _calculateNewClearingPrice(Tick memory tickUpper, Tick memory tickLower, uint256 blockTokenSupply)
        internal
        view
        returns (uint256 newClearingPrice)
    {
        Demand memory _sumDemandAboveClearing = sumDemandAboveClearing;
        uint256 blockDemandAboveClearing =
            _sumDemandAboveClearing.resolve(tickUpper.price, tickSpacing).applyMps(step.mps);
        // If there is no demand above the clearing price or the demand is equal to the block supply, the clearing price is tickUpper
        // This can happen in a few scenarios:
        // 1. The auction just started and the tickUpper represents the floor price and should be returned
        // 2. There is fully matching demand at tickUpper, so it should be new clearing price
        // 3. There is no demand above the current clearing price, so TickUpper is the highest tick in the book and should be new clearing price
        if (blockDemandAboveClearing == 0 || blockDemandAboveClearing == blockTokenSupply) return tickUpper.price;

        // blockDemandAboveClearing must be < blockTokenSupply here
        Demand memory sumDemandTickLower = _sumDemandAboveClearing.add(tickLower.demand);
        newClearingPrice = sumDemandTickLower.currencyDemand.applyMps(step.mps).fullMulDiv(
            tickSpacing, (blockTokenSupply - sumDemandTickLower.tokenDemand.applyMps(step.mps))
        );
        newClearingPrice -= (newClearingPrice % tickSpacing);
    }

    /// @notice Update the checkpoint
    /// @param _checkpoint The checkpoint to update
    /// @param _clearingPrice The new clearing price
    /// @param _blockTokenSupply The token supply at or above tickUpper in the block
    /// @return The updated checkpoint
    function _updateCheckpoint(Checkpoint memory _checkpoint, uint256 _clearingPrice, uint256 _blockTokenSupply)
        internal
        view
        returns (Checkpoint memory)
    {
        // Set the clearing price to the floorPrice if it is lower
        if (_clearingPrice <= floorPrice) {
            _checkpoint.clearingPrice = floorPrice;
            // We can only clear the current demand at the floor price
            _checkpoint.totalCleared += sumDemandAboveClearing.resolve(floorPrice, tickSpacing).applyMps(step.mps);
        }
        // Otherwise, we can clear the entire supply being sold in the block
        else {
            _checkpoint.clearingPrice = _clearingPrice;
            _checkpoint.totalCleared += _blockTokenSupply;
        }

        uint24 mpsSinceLastCheckpoint = (
            step.mps
                * (block.number - (step.startBlock > lastCheckpointedBlock ? step.startBlock : lastCheckpointedBlock))
        ).toUint24();

        _checkpoint.cumulativeMps += mpsSinceLastCheckpoint;
        _checkpoint.cumulativeMpsPerPrice +=
            uint256(mpsSinceLastCheckpoint).fullMulDiv(BidLib.PRECISION, _checkpoint.clearingPrice);
        _checkpoint.resolvedDemandAboveClearingPrice =
            sumDemandAboveClearing.resolve(_checkpoint.clearingPrice, tickSpacing);
        _checkpoint.blockCleared = _blockTokenSupply;
        _checkpoint.mps = step.mps;
        _checkpoint.prev = lastCheckpointedBlock;

        return _checkpoint;
    }

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() public returns (Checkpoint memory _checkpoint) {
        if (block.number < startBlock) revert AuctionNotStarted();

        // Advance to the current step if needed, summing up the results since the last checkpointed block
        _checkpoint = _advanceToCurrentStep();

        uint256 blockTokenSupply = (totalSupply - _checkpoint.totalCleared).fullMulDiv(
            step.mps, AuctionStepLib.MPS - _checkpoint.cumulativeMps
        );

        // All active demand above the current clearing price
        Demand memory _sumDemandAboveClearing = sumDemandAboveClearing;

        Tick memory _tickUpper = ticks[tickUpperId];
        // Resolve the demand at the next initialized tick
        // Find the tick which does not fully match the supply, or the highest tick in the book
        while (_sumDemandAboveClearing.resolve(_tickUpper.price, tickSpacing).applyMps(step.mps) >= blockTokenSupply) {
            // Subtract the demand at the current tickUpper before advancing to the next tick
            _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_tickUpper.demand);
            // If there is no future tick, break to avoid ending up in a bad state
            if (_tickUpper.next == 0) {
                break;
            }
            _tickUpper = ticks[_tickUpper.next];
            tickUpperId = _tickUpper.id;
        }

        sumDemandAboveClearing = _sumDemandAboveClearing;

        uint256 newClearingPrice = _calculateNewClearingPrice(_tickUpper, ticks[_tickUpper.prev], blockTokenSupply);
        _checkpoint = _updateCheckpoint(_checkpoint, newClearingPrice, blockTokenSupply);
        _insertCheckpoint(_checkpoint);

        emit CheckpointUpdated(
            block.number, _checkpoint.clearingPrice, _checkpoint.totalCleared, _checkpoint.cumulativeMps
        );
    }

    function _submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        // First bid in a block updates the clearing price
        if (lastCheckpointedBlock != block.number) checkpoint();

        uint128 tickId = _initializeTickIfNeeded(prevHintId, maxPrice);

        if (address(validationHook) != address(0)) {
            validationHook.validate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        }
        uint256 _clearingPrice = clearingPrice();
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        BidLib.validate(maxPrice, _clearingPrice, tickSpacing);

        _updateTick(tickId, exactIn, amount);

        bidId = _createBid(exactIn, amount, owner, tickId);

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
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, tickSpacing);
        if (resolvedAmount == 0) revert InvalidAmount();
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        return _submitBid(maxPrice, exactIn, amount, owner, prevHintId, hookData);
    }

    /// @notice Given a bid, tokens filled and refund, process the transfers and refund
    function _processBidWithdraw(uint256 bidId, Bid memory bid, uint256 tokensFilled, uint256 refund) internal {
        address _owner = bid.owner;

        if (tokensFilled == 0) {
            _deleteBid(bidId);
        } else {
            bid.tokensFilled = tokensFilled;
            bid.withdrawnBlock = uint64(block.number);
            _updateBid(bidId, bid);
        }

        currency.transfer(_owner, refund);

        emit BidWithdrawn(bidId, _owner);
    }

    /// @inheritdoc IAuction
    function withdrawBid(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.withdrawnBlock != 0) revert BidAlreadyWithdrawn();
        Tick memory tick = ticks[bid.tickId];
        if (block.number <= endBlock || tick.price <= clearingPrice()) revert CannotWithdrawBid();

        /// @dev Bid was fully filled and the auction is now over
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        (uint256 tokensFilled, uint24 cumulativeMpsDelta) = _accountFullyFilledCheckpoints(
            latestCheckpoint().transform(lastCheckpointedBlock, endBlock - lastCheckpointedBlock, step.mps),
            startCheckpoint,
            bid
        );
        uint256 refund = bid.calculateRefund(
            tick.price, tokensFilled, cumulativeMpsDelta, AuctionStepLib.MPS - startCheckpoint.cumulativeMps
        );

        _processBidWithdraw(bidId, bid, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function withdrawPartiallyFilledBid(uint256 bidId, uint256 upperCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.withdrawnBlock != 0) revert BidAlreadyWithdrawn();

        Tick memory tick = ticks[bid.tickId];

        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        // Upper checkpoint is the first checkpoint where the clearing price is strictly > tick.price
        Checkpoint memory upperCheckpoint = _getCheckpoint(upperCheckpointBlock);
        // Last valid checkpoint is the last checkpoint where the clearing price is <= tick.price
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(upperCheckpoint.prev);

        uint256 tokensFilled;
        uint24 cumulativeMpsDelta;
        uint256 _clearingPrice = clearingPrice();
        /// @dev Bid has been outbid
        if (tick.price < _clearingPrice) {
            if (lastValidCheckpoint.clearingPrice > tick.price) revert InvalidCheckpointHint();

            uint256 nextCheckpointBlock;
            (tokensFilled, cumulativeMpsDelta, nextCheckpointBlock) =
                _accountPartiallyFilledCheckpoints(lastValidCheckpoint, tick, bid);
            /// Now account for the fully filled checkpoints until the startCheckpoint
            (uint256 _tokensFilled, uint24 _cumulativeMpsDelta) =
                _accountFullyFilledCheckpoints(_getCheckpoint(nextCheckpointBlock), startCheckpoint, bid);
            tokensFilled += _tokensFilled;
            cumulativeMpsDelta += _cumulativeMpsDelta;
        } else if (block.number > endBlock && tick.price == _clearingPrice) {
            /// @dev Bid is partially filled at the end of the auction, tick.price must be equal to the clearing price
            if (upperCheckpoint.clearingPrice < tick.price || lastValidCheckpoint.clearingPrice > tick.price) {
                revert InvalidCheckpointHint();
            }

            // Calculate the tokens sold and proportion of input used to bidders of a price (p)
            // The tokens sold to bidders of a price (p) is equal to the supply sold `S` as a
            // proportion of the demand at `p` of the total demand at or above the clearing price.
            //
            // Setup:
            // lastValidCheckpoint --- ... | upperCheckpoint --- ... | latestCheckpoint ... | endBlock
            // price < clearingPrice       | clearingPrice == price -------------------------->
            //
            // We can calculate the tokens sold and proportion of input used to bidders of a price (p)
            // by using the fully filled checkpoints and then applying the proportion of the bid demand at the price level to the values

            (tokensFilled, cumulativeMpsDelta) =
                _accountFullyFilledCheckpoints(lastValidCheckpoint, startCheckpoint, bid);
            (uint256 partialTokensFilled, uint24 partialCumulativeMpsDelta,) = _accountPartiallyFilledCheckpoints(
                latestCheckpoint().transform(lastCheckpointedBlock, endBlock - lastCheckpointedBlock, step.mps),
                tick,
                bid
            );
            tokensFilled += partialTokensFilled;
            cumulativeMpsDelta += partialCumulativeMpsDelta;
        } else {
            revert CannotWithdrawBid();
        }

        uint256 refund = bid.calculateRefund(
            tick.price, tokensFilled, cumulativeMpsDelta, AuctionStepLib.MPS - startCheckpoint.cumulativeMps
        );

        _processBidWithdraw(bidId, bid, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.withdrawnBlock == 0) revert BidNotWithdrawn();
        if (block.number < claimBlock) revert NotClaimable();

        uint256 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        token.transfer(bid.owner, tokensFilled);

        emit TokensClaimed(bid.owner, tokensFilled);
    }

    /// @notice Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints
    /// @dev This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
    ///      because it uses lazy accounting to calculate the tokens filled
    /// @param upper The upper checkpoint
    /// @param lower The lower checkpoint
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return cumulativeMpsDelta The proportion of input used
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory lower, Bid memory bid)
        internal
        pure
        returns (uint256 tokensFilled, uint24 cumulativeMpsDelta)
    {
        cumulativeMpsDelta = upper.cumulativeMps - lower.cumulativeMps;
        tokensFilled = bid.calculateFill(
            upper.cumulativeMpsPerPrice - lower.cumulativeMpsPerPrice,
            cumulativeMpsDelta,
            AuctionStepLib.MPS - lower.cumulativeMps
        );
    }

    function _accountPartiallyFilledCheckpoints(Checkpoint memory upper, Tick memory tick, Bid memory bid)
        internal
        view
        returns (uint256 tokensFilled, uint24 cumulativeMpsDelta, uint256 nextCheckpointBlock)
    {
        uint256 bidDemand = bid.demand(tick.price, tickSpacing);
        uint256 tickDemand = tick.resolveDemand(tickSpacing);
        while (upper.prev != 0) {
            Checkpoint memory _next = _getCheckpoint(upper.prev);
            // Stop when the next checkpoint is less than the tick price
            if (_next.clearingPrice < tick.price) {
                // Upper is the last checkpoint where tick.price == clearingPrice
                // Account for tokens sold in the upperCheckpoint block, since checkpoint ranges are not inclusive [start,end)
                (uint256 _upperCheckpointTokensFilled, uint24 _upperCheckpointSupplyMps) = _partialFill(
                    upper.blockCleared, upper.mps, upper.resolvedDemandAboveClearingPrice, bidDemand, tickDemand
                );
                tokensFilled += _upperCheckpointTokensFilled;
                cumulativeMpsDelta += _upperCheckpointSupplyMps;
                break;
            }
            (uint256 _tokensFilled, uint24 _cumulativeMpsDelta) = _partialFill(
                upper.totalCleared - _next.totalCleared,
                upper.cumulativeMps - _next.cumulativeMps,
                upper.resolvedDemandAboveClearingPrice,
                bidDemand,
                tickDemand
            );
            tokensFilled += _tokensFilled;
            cumulativeMpsDelta += _cumulativeMpsDelta;
            upper = _next;
        }
        return (tokensFilled, cumulativeMpsDelta, upper.prev);
    }

    function _partialFill(
        uint256 supply,
        uint24 mpsDelta,
        uint256 resolvedDemandAboveClearingPrice,
        uint256 bidDemand,
        uint256 tickDemand
    ) internal view returns (uint256 tokensFilled, uint24 cumulativeMpsDelta) {
        uint256 _bidDemandMps = bidDemand.applyMps(mpsDelta);
        uint256 _tickDemandMps = tickDemand.applyMps(mpsDelta);
        uint256 supplySoldToTick = supply - resolvedDemandAboveClearingPrice.applyMps(mpsDelta);
        tokensFilled = supplySoldToTick.fullMulDiv(_bidDemandMps, tickSpacing * _tickDemandMps);
        cumulativeMpsDelta = (
            uint256(mpsDelta).fullMulDiv(supplySoldToTick, _tickDemandMps).fullMulDiv(_bidDemandMps, _tickDemandMps)
        ).toUint24();
    }

    receive() external payable {}
}
