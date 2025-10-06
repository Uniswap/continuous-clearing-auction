// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {TokenCurrencyStorage} from './TokenCurrencyStorage.sol';
import {AuctionParameters, IAuction} from './interfaces/IAuction.sol';
import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {CheckpointLib} from './libraries/CheckpointLib.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {SupplyLib, SupplyRolloverMultiplier} from './libraries/SupplyLib.sol';
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './libraries/ValueX7X7Lib.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
/// @custom:security-contact security@uniswap.org
/// @notice Implements a time weighted uniform clearing price auction
/// @dev Can be constructed directly or through the AuctionFactory. In either case, users must validate
///      that the auction parameters are correct and it has sufficient token balance.
contract Auction is
    BidStorage,
    CheckpointStorage,
    AuctionStepStorage,
    TickStorage,
    PermitSingleForwarder,
    TokenCurrencyStorage,
    IAuction
{
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using BidLib for *;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using SafeCastLib for uint256;
    using ValidationHookLib for IValidationHook;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using SupplyLib for *;

    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook internal immutable VALIDATION_HOOK;
    /// @notice The total currency that will be raised selling total supply at the floor price
    ValueX7X7 internal immutable TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7;

    /// @notice The sum of currency demand in ticks above the clearing price
    /// @dev This will increase every time a new bid is submitted, and decrease when bids are outbid.
    ValueX7 internal $sumCurrencyDemandAboveClearingX7;
    /// @notice Whether the TOTAL_SUPPLY of tokens has been received
    bool private $_tokensReceived;
    /// @notice A packed uint256 containing `set`, `remainingSupplyX7X7`, and `remainingMps` values derived from the checkpoint
    ///         immediately before the auction becomes fully subscribed. The ratio of these helps account for rollover supply.
    SupplyRolloverMultiplier internal $_supplyRolloverMultiplier;

    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        TokenCurrencyStorage(
            _token,
            _parameters.currency,
            _totalSupply,
            _parameters.tokensRecipient,
            _parameters.fundsRecipient
        )
        TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        CLAIM_BLOCK = _parameters.claimBlock;
        VALIDATION_HOOK = IValidationHook(_parameters.validationHook);

        if (CLAIM_BLOCK < END_BLOCK) revert ClaimBlockIsBeforeEndBlock();

        // Calculate the total currency that will be raised from selling the total supply at the floor price
        TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7 = TOTAL_SUPPLY_X7_X7.wrapAndFullMulDivUp(FLOOR_PRICE, FixedPoint96.Q96);
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (block.number < END_BLOCK) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for functions which can only be called after the auction is started and the tokens have been received
    modifier onlyActiveAuction() {
        if (block.number < START_BLOCK) revert AuctionNotStarted();
        if (!$_tokensReceived) revert TokensNotReceived();
        _;
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external {
        // Don't check balance or emit the TokensReceived event if the tokens have already been received
        if ($_tokensReceived) return;
        // Use the normal totalSupply value instead of the scaled up X7 value
        if (TOKEN.balanceOf(address(this)) < TOTAL_SUPPLY) {
            revert InvalidTokenAmountReceived();
        }
        $_tokensReceived = true;
        emit TokensReceived(TOTAL_SUPPLY);
    }

    /// @inheritdoc IAuction
    function isGraduated() external view returns (bool) {
        return _isGraduated(latestCheckpoint());
    }

    /// @notice Whether the auction has graduated as of the given checkpoint
    /// @dev The auction is considered `graudated` if the clearing price is greater than the floor price
    ///      since that means it has sold all of the total supply of tokens.
    function _isGraduated(Checkpoint memory _checkpoint) internal view returns (bool) {
        return _checkpoint.clearingPrice > FLOOR_PRICE;
    }

    /// @notice Return a new checkpoint after advancing the current checkpoint by some `mps`
    ///         This function updates the cumulative values of the checkpoint, and
    ///         requires that the clearing price is up to date
    /// @param _checkpoint The checkpoint to sell tokens at its clearing price
    /// @param deltaMps The number of mps to sell
    /// @return The checkpoint with all cumulative values updated
    function _sellTokensAtClearingPrice(Checkpoint memory _checkpoint, uint24 deltaMps)
        internal
        returns (Checkpoint memory)
    {
        ValueX7X7 currencyRaisedX7X7;
        // If the clearing price is above the floor price, the auction is fully subscribed and the amount of
        // currency which will be raised is deterministic based on the initial supply schedule.
        if (_checkpoint.clearingPrice > FLOOR_PRICE) {
            // We get the cached remaining currencyRaisedX7X7 and remaining mps for use in the calculations below.
            // These values are the numerator and denominator (respectively) of the factor which we use
            // to ensure we are correctly rolling over unsold supply in the blocks before the auction became fully subscribed.
            (bool isSet, uint24 cachedRemainingPercentage, ValueX7X7 cachedRemainingCurrencyRaisedX7X7) =
                $_supplyRolloverMultiplier.unpack();
            if (!isSet) {
                // Locally set the variables to save gas
                cachedRemainingPercentage = ConstantsLib.MPS - _checkpoint.cumulativeMps;
                cachedRemainingCurrencyRaisedX7X7 =
                    TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7.sub(_checkpoint.totalCurrencyRaisedX7X7);
                // Set the cache with the values in _checkpoint, which represents the state of the auction before it becomes fully subscribed
                $_supplyRolloverMultiplier = SupplyLib.packSupplyRolloverMultiplier(
                    true, cachedRemainingPercentage, cachedRemainingCurrencyRaisedX7X7
                );
            }
            // The currency raised is equal to multiplying the ratio between actualized currency raised and expected
            // by the current clearing price, and the number of mps according to the original supply schedule
            // and finally dividing by the floor price.
            currencyRaisedX7X7 = cachedRemainingCurrencyRaisedX7X7.wrapAndFullMulDiv(
                _checkpoint.clearingPrice * uint256(deltaMps), uint256(cachedRemainingPercentage) * FLOOR_PRICE
            );

            // There is a special case where the clearing price is at a tick boundary with bids.
            // In this case, we have to explicitly track the supply sold to that price since they are "partially filled"
            // and thus the amount of tokens sold to that price is <= to the collective demand at that price, since bidders at higher prices are prioritized.
            if (
                _checkpoint.clearingPrice % TICK_SPACING == 0
                    && !_getTick(_checkpoint.clearingPrice).currencyDemandX7.eq(ValueX7.wrap(0))
            ) {
                // The currencyRaisedAtClearingPrice is simply the total currency raised from the supply schedule
                // minus the currency raised from the demand above the clearing price.
                // We should divide the sumDemandAboveClearing by 1e7 (100%) to get the actualized currency raised, but
                // to avoid intermediate division, we upcast it into a X7X7 value to show that it has implicitly been scaled up by 1e7.
                ValueX7X7 currencyRaisedAtClearingPriceX7X7 =
                    currencyRaisedX7X7.sub($sumCurrencyDemandAboveClearingX7.mulUint256(deltaMps).upcast());
                // Update the cumulative value in the checkpoint which will be reset if the clearing price changes
                _checkpoint.cumulativeCurrencyRaisedAtClearingPriceX7X7 =
                    _checkpoint.cumulativeCurrencyRaisedAtClearingPriceX7X7.add(currencyRaisedAtClearingPriceX7X7);
            }
        }
        // In the case where the auction is not fully subscribed yet, we can only sell tokens equal to the current demand above the clearing price
        else {
            // Calculate the currency raised from the total demand above the clearing price
            // This should be divided by 1e7, but we scale it up instead to avoid the division.
            // This is why we upcast() to show that it implicitly has been scaled up by 1e7.
            currencyRaisedX7X7 = $sumCurrencyDemandAboveClearingX7.mulUint256(deltaMps).upcast();
        }
        _checkpoint.totalCurrencyRaisedX7X7 = _checkpoint.totalCurrencyRaisedX7X7.add(currencyRaisedX7X7);
        _checkpoint.cumulativeMps += deltaMps;
        // Calculate the harmonic mean of the mps and price
        _checkpoint.cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(deltaMps, _checkpoint.clearingPrice);
        return _checkpoint;
    }

    /// @notice Fast forward to the current step, selling tokens at the current clearing price according to the supply schedule
    /// @dev The checkpoint MUST have the most up to date clearing price since `sellTokensAtClearingPrice` depends on it
    function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint64 blockNumber)
        internal
        returns (Checkpoint memory)
    {
        // Advance the current step until the current block is within the step
        // Start at the larger of the last checkpointed block or the start block of the current step
        uint64 start = $step.startBlock < $lastCheckpointedBlock ? $lastCheckpointedBlock : $step.startBlock;
        uint64 end = $step.endBlock;

        uint24 mps = $step.mps;
        while (blockNumber > end) {
            _checkpoint = _sellTokensAtClearingPrice(_checkpoint, uint24((end - start) * mps));
            start = end;
            if (end == END_BLOCK) break;
            AuctionStep memory _step = _advanceStep();
            mps = _step.mps;
            end = _step.endBlock;
        }
        return _checkpoint;
    }

    /// @notice Calculate the new clearing price, given the cumulative demand and the remaining supply in the auction
    /// @param _tickLowerPrice The price of the tick which we know we have enough demand to clear
    /// @param _sumCurrencyDemandAboveClearingX7 The cumulative demand above the clearing price
    /// @param _cachedRemainingCurrencyRaisedX7X7 The cached remaining currency raised at the floor price
    /// @param _cachedRemainingMps The cached remaining mps in the auction
    /// @return The new clearing price
    function _calculateNewClearingPrice(
        uint256 _tickLowerPrice,
        ValueX7 _sumCurrencyDemandAboveClearingX7,
        ValueX7X7 _cachedRemainingCurrencyRaisedX7X7,
        uint24 _cachedRemainingMps
    ) internal view returns (uint256) {
        /**
         * We can calculate the new clearing price using the formula:
         * currency demand above tick lower * tickLowerPrice
         * -------------------------------------------------
         * required currency at tick lower
         *
         * Remembering that we can find the required currency at tick lower by using the
         * scaling factory of cachedRemainingCurrencyRaisedX7X7 and cachedRemainingMps,
         * multiplying that by the tickLowerPrice and dividing by the floorPrice.
         *
         * Substituting that in, and multiplying by the reciprical we get:
         *                                                                _cachedRemainingMps * floorPrice
         * currency demand above tick lower * tickLowerPrice  * ---------------------------------------------------
         *                                                      _cachedRemainingCurrencyRaisedX7X7 * tickLowerPrice
         *
         * Observe that we can cancel out the tickLowerPrice from the numerator and denominator,
         * and we already have currency demand above tick lower from our iteration over ticks, leaving us with:
         *
         * sumCurrencyDemandAboveClearingX7 * floorPrice * _cachedRemainingMps
         *    -------------------------------------------------
         *              _cachedRemainingCurrencyRaisedX7X7
         *
         * The result of this may be lower than tickLowerPrice. That just means that we can't clear at any price above.
         * And we should clear at tickLowerPrice instead.
         */
        uint256 clearingPrice = ValueX7.unwrap(
            _sumCurrencyDemandAboveClearingX7.fullMulDivUp(
                ValueX7.wrap(uint256(_cachedRemainingMps) * FLOOR_PRICE), _cachedRemainingCurrencyRaisedX7X7.downcast()
            )
        );
        if (clearingPrice < _tickLowerPrice) return _tickLowerPrice;
        return clearingPrice;
    }

    /// @notice Iterate to find the tick where the total demand at and above it is strictly less than the remaining supply in the auction
    /// @dev If the loop reaches the highest tick in the book, `nextActiveTickPrice` will be set to MAX_TICK_PTR
    /// @param _checkpoint The latest checkpoint
    /// @return The new clearing price
    function _iterateOverTicksAndFindClearingPrice(Checkpoint memory _checkpoint) internal returns (uint256) {
        // The clearing price can never be lower than the last checkpoint.
        // If the clearingPrice is zero, this will set it to the floor price
        uint256 minimumClearingPrice = _checkpoint.clearingPrice.coalesce(FLOOR_PRICE);
        (bool isSet, uint24 cachedRemainingPercentage, ValueX7X7 cachedRemainingCurrencyRaisedX7X7) =
            $_supplyRolloverMultiplier.unpack();
        uint24 remainingMpsInAuction = isSet ? cachedRemainingPercentage : _checkpoint.remainingMpsInAuction();
        ValueX7X7 remainingCurrencyRaisedAtFloorX7X7 = isSet
            ? cachedRemainingCurrencyRaisedX7X7
            : TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7.sub(_checkpoint.totalCurrencyRaisedX7X7);
        // If there are no more remaining mps in the auction, we don't need to iterate over ticks
        // and we can return the minimum clearing price above
        if (remainingMpsInAuction == 0) return minimumClearingPrice;

        // Place state variables on the stack to save gas
        bool updateStateVariables;
        ValueX7 sumCurrencyDemandAboveClearingX7_ = $sumCurrencyDemandAboveClearingX7;
        uint256 nextActiveTickPrice_ = $nextActiveTickPrice;

        /**
         * Tick iteration loop explained:
         *
         * We have the current demand above the clearing price, and we want to see if it is enough to fully purchase
         * all of the remaining supply being sold at the nextActiveTickPrice. We only need to check `nextActiveTickPrice`
         * because we know that there are no bids in between the current clearing price and that price.
         *
         * Observe that we need a certain amount of collective demand to increase the auction from the floor price.
         * - This is equal to `totalSupply * floorPrice`
         *
         * If the auction was fully subscribed in the first block which it was active, then the total CURRENCY REQUIRED
         * at any given price is equal to totalSupply * p', where p' is that price.
         *
         * However, if the auction is not fully subscribed from the start, there will be excess supply which will be rolled
         * over into future blocks. This means that the amount of currency required to change the clearing price no longer
         * follows the formula above because we are no longer following the original supply schedule.
         *
         * Instead, we need to linearly transform the supply schedule to account for any rollover supply.
         * Observe that we track the total currency raised in the auction, and the remaining percentage of the auction.
         * The ratio of these two values represents how closely the auction is following the original supply schedule.
         * Once the auction is fully subscribed, both the numerator and denominator will increase at the same rate.
         * The numerator and denominator of this factor are stored within $_supplyRolloverMultiplier.
         *
         * The moment when the auction becomes fully subscribed, we can freeze this ratio and apply it to the existing
         * supply schedule to determinstically calculate the amount of currency required to move the auction to any given price.
         *
         * This scaling factor is defined as: (pseudocode)
         *
         *            totalSupply - cumulativeTokensSold
         *   F = -------------------------------------------
         *           percentageRemainingInAuction
         *
         * We don't track actual tokens sold because it requires division.
         * Thus, we multiply this by `floorPrice` so it is in terms of currency.
         *
         *       floorPrice * (totalSupply - cumulativeTokensSold)
         *   F = -------------------------------------------------
         *                percentageRemainingInAuction
         *
         * And this is what we save in state:
         *
         *       TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7 - totalCurrencyRaisedX7X7
         *   F = ---------------------------------------------------------------
         *                  ConstantsLib.MPS - _checkpoint.cumulativeMps
         *
         * Notice that floorPrice * totalSupply == TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7
         * and floorPrice * cumulativeTokensSold == totalCurrencyRaisedX7X7 (from selling tokens at floor price)
         *
         * This means that the currency required to move the auction to any given price p' is:
         *
         *                                            F * p'
         *   currencyRequiredAtNextActiveTickPrice = ----------
         *                                           floorPrice
         *
         * Because `F` includes a division by `(ConstantsLib.MPS - _checkpoint.cumulativeMps)`, we can multiply both sides
         * by `(ConstantsLib.MPS - _checkpoint.cumulativeMps)` to get:
         *
         *   currencyRequiredAtNextActiveTickPrice * (ConstantsLib.MPS - _checkpoint.cumulativeMps)
         * s
         *        >= (TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7 - totalCurrencyRaisedX7X7) * nextActiveTickPrice_
         *           --------------------------------------------------------------------------------------
         *                                            floorPrice
         */
        Tick memory nextActiveTick = _getTick(nextActiveTickPrice_);
        while (
            nextActiveTickPrice_ != MAX_TICK_PTR
            // Loop while the currency amount above `nextActiveTickPrice_` is greater than the required currency at nextActiveTickPrice_
            && sumCurrencyDemandAboveClearingX7_.mulUint256(remainingMpsInAuction).upcast().gte(
                // Round down here to bias towards iterating over the next tick
                remainingCurrencyRaisedAtFloorX7X7.wrapAndFullMulDiv(nextActiveTickPrice_, FLOOR_PRICE)
            )
        ) {
            // Subtract the demand at the current nextActiveTick from the total demand
            sumCurrencyDemandAboveClearingX7_ = sumCurrencyDemandAboveClearingX7_.sub(nextActiveTick.currencyDemandX7);
            // Save the previous next active tick price
            minimumClearingPrice = nextActiveTickPrice_;
            // Advance to the next tick
            nextActiveTickPrice_ = nextActiveTick.next;
            nextActiveTick = _getTick(nextActiveTickPrice_);
            updateStateVariables = true;
        }
        // Set the values into storage if we found a new next active tick price
        if (updateStateVariables) {
            $sumCurrencyDemandAboveClearingX7 = sumCurrencyDemandAboveClearingX7_;
            $nextActiveTickPrice = nextActiveTickPrice_;
            emit NextActiveTickUpdated(nextActiveTickPrice_);
        }

        // Calculate the new clearing price
        uint256 clearingPrice = _calculateNewClearingPrice(
            minimumClearingPrice,
            sumCurrencyDemandAboveClearingX7_,
            remainingCurrencyRaisedAtFloorX7X7,
            remainingMpsInAuction
        );
        return clearingPrice;
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @dev This updates the state of the auction accounting for the bids placed after the last checkpoint
    ///      Checkpoints are created at the top of each block with a new bid and does NOT include that bid
    ///      Because of this, we need to calculate what the new state of the Auction should be before updating
    ///      purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingX7` value
    /// @param blockNumber The block number to checkpoint at
    function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        if (blockNumber == $lastCheckpointedBlock) return latestCheckpoint();

        _checkpoint = latestCheckpoint();
        uint256 clearingPrice = _iterateOverTicksAndFindClearingPrice(_checkpoint);
        if (clearingPrice != _checkpoint.clearingPrice) {
            // Set the new clearing price
            _checkpoint.clearingPrice = clearingPrice;
            _checkpoint.cumulativeCurrencyRaisedAtClearingPriceX7X7 = ValueX7X7.wrap(0);
            emit ClearingPriceUpdated(blockNumber, clearingPrice);
        }

        // Sine the clearing price is now up to date, we can advance the auction to the current step
        // and sell tokens at the current clearing price according to the supply schedule
        _checkpoint = _advanceToCurrentStep(_checkpoint, blockNumber);

        // Now account for any time in between this checkpoint and the greater of the start of the step or the last checkpointed block
        uint64 blockDelta =
            blockNumber - ($step.startBlock > $lastCheckpointedBlock ? $step.startBlock : $lastCheckpointedBlock);
        uint24 mpsSinceLastCheckpoint = uint256($step.mps * blockDelta).toUint24();

        // Sell the percentage of outstanding tokens since the last checkpoint to the current clearing price
        _checkpoint = _sellTokensAtClearingPrice(_checkpoint, mpsSinceLastCheckpoint);
        // Insert the checkpoint into storage, updating latest pointer and the linked list
        _insertCheckpoint(_checkpoint, blockNumber);

        emit CheckpointUpdated(
            blockNumber, _checkpoint.clearingPrice, _checkpoint.totalCurrencyRaisedX7X7, _checkpoint.cumulativeMps
        );
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory) {
        return _unsafeCheckpoint(END_BLOCK);
    }

    function _submitBid(uint256 maxPrice, uint256 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        internal
        returns (uint256 bidId)
    {
        Checkpoint memory _checkpoint = checkpoint();
        // Revert if there are no more tokens to be sold
        if (_checkpoint.remainingMpsInAuction() == 0) revert AuctionSoldOut();

        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        VALIDATION_HOOK.handleValidate(maxPrice, amount, owner, msg.sender, hookData);
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        if (maxPrice <= _checkpoint.clearingPrice || maxPrice >= BidLib.MAX_BID_PRICE) revert InvalidBidPrice();

        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        Bid memory bid;
        (bid, bidId) = _createBid(amount, owner, maxPrice, _checkpoint.cumulativeMps);
        ValueX7 bidEffectiveAmount = bid.toEffectiveAmount();

        _updateTickDemand(maxPrice, bidEffectiveAmount);

        $sumCurrencyDemandAboveClearingX7 = $sumCurrencyDemandAboveClearingX7.add(bidEffectiveAmount);

        // If the sumDemandAboveClearing becomes large enough to overflow a multiplication an X7 value, revert
        if ($sumCurrencyDemandAboveClearingX7.gte(ValueX7.wrap(ConstantsLib.X7_UPPER_BOUND))) {
            revert InvalidBidUnableToClear();
        }

        emit BidSubmitted(bidId, owner, maxPrice, amount);
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
            CURRENCY.transfer(_owner, refund);
        }

        emit BidExited(bidId, _owner, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function checkpoint() public onlyActiveAuction returns (Checkpoint memory) {
        if (block.number > END_BLOCK) {
            return _getFinalCheckpoint();
        }
        return _unsafeCheckpoint(uint64(block.number));
    }

    /// @inheritdoc IAuction
    /// @dev Bids can be submitted anytime between the startBlock and the endBlock.
    function submitBid(uint256 maxPrice, uint256 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        public
        payable
        onlyActiveAuction
        returns (uint256)
    {
        // Bids cannot be submitted at the endBlock or after
        if (block.number >= END_BLOCK) revert AuctionIsOver();
        // If the bid is too small such that it would be rounded down to zero, revert
        if (amount < BidLib.MIN_BID_AMOUNT) revert BidAmountTooSmall();
        // If the bid would overflow a ValueX7X7 value, revert
        if (amount > BidLib.MAX_BID_AMOUNT) revert BidAmountTooLarge();
        if (CURRENCY.isAddressZero()) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert CurrencyIsNotNative();
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(CURRENCY), msg.sender, address(this), amount);
        }
        return _submitBid(maxPrice, amount, owner, prevTickPrice, hookData);
    }

    /// @inheritdoc IAuction
    function submitBid(uint256 maxPrice, uint256 amount, address owner, bytes calldata hookData)
        public
        payable
        onlyActiveAuction
        returns (uint256)
    {
        return submitBid(maxPrice, amount, owner, FLOOR_PRICE, hookData);
    }

    /// @inheritdoc IAuction
    function exitBid(uint256 bidId) external onlyAfterAuctionIsOver {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        if (!_isGraduated(finalCheckpoint)) {
            // In the case that the auction did not graduate, fully refund the bid
            return _processExit(bidId, bid, 0, bid.amount);
        }

        if (bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();
        /// @dev Bid was fully filled and the auction is now over
        (uint256 tokensFilled, uint256 currencySpent) =
            _accountFullyFilledCheckpoints(finalCheckpoint, _getCheckpoint(bid.startBlock), bid);

        _processExit(bidId, bid, tokensFilled, bid.amount - currencySpent);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 outbidBlock)
        external
    {
        // Checkpoint before checking any of the hints because they could depend on the latest checkpoint
        // Calling this function after the auction is over will return the final checkpoint
        Checkpoint memory currentBlockCheckpoint = checkpoint();

        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        // If the provided hint is the current block, use the checkpoint returned by `checkpoint()` instead of getting it from storage
        Checkpoint memory lastFullyFilledCheckpoint = lastFullyFilledCheckpointBlock == block.number
            ? currentBlockCheckpoint
            : _getCheckpoint(lastFullyFilledCheckpointBlock);
        // There is guaranteed to be a checkpoint at the bid's startBlock because we always checkpoint before bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);

        // Since `lower` points to the last fully filled Checkpoint, it must be < bid.maxPrice
        // The next Checkpoint after `lower` must be partially or fully filled (clearingPrice >= bid.maxPrice)
        // `lower` also cannot be before the bid's startCheckpoint
        if (
            lastFullyFilledCheckpoint.clearingPrice >= bid.maxPrice
                || _getCheckpoint(lastFullyFilledCheckpoint.next).clearingPrice < bid.maxPrice
                || lastFullyFilledCheckpointBlock < bid.startBlock
        ) {
            revert InvalidLastFullyFilledCheckpointHint();
        }

        uint256 tokensFilled;
        uint256 currencySpent;
        // If the lastFullyFilledCheckpoint is not 0, account for the fully filled checkpoints
        if (lastFullyFilledCheckpoint.clearingPrice > 0) {
            (tokensFilled, currencySpent) =
                _accountFullyFilledCheckpoints(lastFullyFilledCheckpoint, startCheckpoint, bid);
        }

        // Upper checkpoint is the last checkpoint where the bid is partially filled
        Checkpoint memory upperCheckpoint;
        // If outbidBlock is not zero, the bid was outbid and the bidder is requesting an early exit
        // This can be done before the auction's endBlock
        if (outbidBlock != 0) {
            // If the provided hint is the current block, use the checkpoint returned by `checkpoint()` instead of getting it from storage
            Checkpoint memory outbidCheckpoint =
                outbidBlock == block.number ? currentBlockCheckpoint : _getCheckpoint(outbidBlock);

            upperCheckpoint = _getCheckpoint(outbidCheckpoint.prev);
            // We require that the outbid checkpoint is > bid max price AND the checkpoint before it is <= bid max price, revert if either of these conditions are not met
            if (outbidCheckpoint.clearingPrice <= bid.maxPrice || upperCheckpoint.clearingPrice > bid.maxPrice) {
                revert InvalidOutbidBlockCheckpointHint();
            }
        } else {
            // The only other partially exitable case is if the auction ends with the clearing price equal to the bid's max price
            // These bids can only be exited after the auction ends
            if (block.number < END_BLOCK) revert CannotPartiallyExitBidBeforeEndBlock();
            // Set the upper checkpoint to the checkpoint returned when we initially called `checkpoint()`
            // This must be the final checkpoint because `checkpoint()` will return the final checkpoint after the auction is over
            upperCheckpoint = currentBlockCheckpoint;
            // Revert if the final checkpoint's clearing price is not equal to the bid's max price
            if (upperCheckpoint.clearingPrice != bid.maxPrice) {
                revert CannotExitBid();
            }
        }

        /**
         * Account for partially filled checkpoints
         *
         *                 <-- fully filled ->  <- partially filled ---------->  INACTIVE
         *                | ----------------- | -------- | ------------------- | ------ |
         *                ^                   ^          ^                     ^        ^
         *              start       lastFullyFilled   lastFullyFilled.next    upper    outbid
         *
         * Instantly partial fill case:
         *
         *                <- partially filled ----------------------------->  INACTIVE
         *                | ----------------- | --------------------------- | ------ |
         *                ^                   ^                             ^        ^
         *              start          lastFullyFilled.next               upper    outbid
         *           lastFullyFilled
         *
         */
        uint256 bidMaxPrice = bid.maxPrice; // place on stack
        if (upperCheckpoint.clearingPrice == bidMaxPrice) {
            (uint256 partialTokensFilled, uint256 partialCurrencySpent) = _accountPartiallyFilledCheckpoints(
                bid, _getTick(bidMaxPrice).currencyDemandX7, upperCheckpoint.cumulativeCurrencyRaisedAtClearingPriceX7X7
            );
            tokensFilled += partialTokensFilled;
            currencySpent += partialCurrencySpent;
        }

        _processExit(bidId, bid, tokensFilled, bid.amount - currencySpent);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 _bidId) external {
        if (block.number < CLAIM_BLOCK) revert NotClaimable();
        if (!_isGraduated(_getFinalCheckpoint())) revert NotGraduated();

        (address owner, uint256 tokensFilled) = _internalClaimTokens(_bidId);
        Currency.wrap(address(TOKEN)).transfer(owner, tokensFilled);

        emit TokensClaimed(_bidId, owner, tokensFilled);
    }

    /// @inheritdoc IAuction
    function claimTokensBatch(address _owner, uint256[] calldata _bidIds) external {
        if (block.number < CLAIM_BLOCK) revert NotClaimable();
        if (!_isGraduated(_getFinalCheckpoint())) revert NotGraduated();

        uint256 tokensFilled = 0;
        for (uint256 i = 0; i < _bidIds.length; i++) {
            (address bidOwner, uint256 bidTokensFilled) = _internalClaimTokens(_bidIds[i]);

            if (bidOwner != _owner) {
                revert BatchClaimDifferentOwner(_owner, bidOwner);
            }

            tokensFilled += bidTokensFilled;

            emit TokensClaimed(_bidIds[i], bidOwner, bidTokensFilled);
        }

        Currency.wrap(address(TOKEN)).transfer(_owner, tokensFilled);
    }

    /// @notice Internal function to claim tokens for a single bid
    /// @param bidId The id of the bid
    /// @return owner The owner of the bid
    /// @return tokensFilled The amount of tokens filled
    function _internalClaimTokens(uint256 bidId) internal returns (address owner, uint256 tokensFilled) {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock == 0) revert BidNotExited();

        // Set return values
        owner = bid.owner;
        tokensFilled = bid.tokensFilled;

        // Set the tokens filled to 0
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);
    }

    /// @inheritdoc IAuction
    function sweepCurrency() external onlyAfterAuctionIsOver {
        // Cannot sweep if already swept
        if (sweepCurrencyBlock != 0) revert CannotSweepCurrency();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        // Cannot sweep currency if the auction has not graduated, as all of the Currency must be refunded
        if (!_isGraduated(finalCheckpoint)) revert NotGraduated();
        _sweepCurrency(finalCheckpoint.getCurrencyRaised());
    }

    /// @inheritdoc IAuction
    function sweepUnsoldTokens() external onlyAfterAuctionIsOver {
        if (sweepUnsoldTokensBlock != 0) revert CannotSweepTokens();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        _sweepUnsoldTokens(_isGraduated(finalCheckpoint) ? 0 : TOTAL_SUPPLY);
    }

    // Getters
    /// @inheritdoc IAuction
    function claimBlock() external view override(IAuction) returns (uint64) {
        return CLAIM_BLOCK;
    }

    /// @inheritdoc IAuction
    function validationHook() external view override(IAuction) returns (IValidationHook) {
        return VALIDATION_HOOK;
    }

    /// @inheritdoc IAuction
    function sumCurrencyDemandAboveClearingX7() external view override(IAuction) returns (ValueX7) {
        return $sumCurrencyDemandAboveClearingX7;
    }
}
