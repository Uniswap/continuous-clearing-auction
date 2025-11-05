// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
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
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
/// @custom:security-contact security@uniswap.org
/// @notice Implements a time weighted uniform clearing price auction
/// @dev Can be constructed directly or through the AuctionFactory. In either case, users must validate
///      that the auction parameters are correct and not incorrectly set.
contract Auction is BidStorage, CheckpointStorage, AuctionStepStorage, TickStorage, TokenCurrencyStorage, IAuction {
    using FixedPointMathLib for *;
    using CurrencyLibrary for Currency;
    using BidLib for *;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using ValidationHookLib for IValidationHook;
    using ValueX7Lib for *;

    /// @notice The maximum price which a bid can be submitted at
    /// @dev Set during construction to type(uint256).max / TOTAL_SUPPLY
    uint256 public immutable MAX_BID_PRICE;
    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook internal immutable VALIDATION_HOOK;

    /// @notice The total currency raised in the auction in Q96 representation, scaled up by X7
    ValueX7 internal $currencyRaisedQ96_X7;
    /// @notice The total tokens sold in the auction so far, in Q96 representation, scaled up by X7
    ValueX7 internal $totalClearedQ96_X7;
    /// @notice The sum of currency demand in ticks above the clearing price
    /// @dev This will increase every time a new bid is submitted, and decrease when bids are outbid.
    uint256 internal $sumCurrencyDemandAboveClearingQ96;
    /// @notice Whether the TOTAL_SUPPLY of tokens has been received
    bool private $_tokensReceived;

    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        TokenCurrencyStorage(
            _token,
            _parameters.currency,
            _totalSupply,
            _parameters.tokensRecipient,
            _parameters.fundsRecipient,
            _parameters.requiredCurrencyRaised
        )
        TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
    {
        CLAIM_BLOCK = _parameters.claimBlock;
        VALIDATION_HOOK = IValidationHook(_parameters.validationHook);

        if (CLAIM_BLOCK < END_BLOCK) revert ClaimBlockIsBeforeEndBlock();

        // We cannot support bids at prices which cause TOTAL_SUPPLY * maxPrice to overflow a uint256
        // However, for tokens with large total supplys and low decimals it would be possible to exceed the Uniswap v4's max tick price
        MAX_BID_PRICE = FixedPointMathLib.min(type(uint256).max / TOTAL_SUPPLY, ConstantsLib.MAX_BID_PRICE);
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (block.number < END_BLOCK) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for claim related functions which can only be called after the claim block
    modifier onlyAfterClaimBlock() {
        if (block.number < CLAIM_BLOCK) revert NotClaimable();
        _;
    }

    /// @notice Modifier for functions which can only be called after the auction is started and the tokens have been received
    modifier onlyActiveAuction() {
        _onlyActiveAuction();
        _;
    }

    /// @notice Internal function to check if the auction is active
    /// @dev Submitting bids or checkpointing is not allowed unless the auction is active
    function _onlyActiveAuction() internal view {
        if (block.number < START_BLOCK) revert AuctionNotStarted();
        if (!$_tokensReceived) revert TokensNotReceived();
    }

    /// @notice Modifier for functions which require the latest checkpoint to be up to date
    modifier ensureEndBlockIsCheckpointed() {
        if ($lastCheckpointedBlock != END_BLOCK) {
            checkpoint();
        }
        _;
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external {
        // Don't check balance or emit the TokensReceived event if the tokens have already been received
        if ($_tokensReceived) return;
        // Use the normal totalSupply value instead of the Q96 value
        if (TOKEN.balanceOf(address(this)) < TOTAL_SUPPLY) {
            revert InvalidTokenAmountReceived();
        }
        $_tokensReceived = true;
        emit TokensReceived(TOTAL_SUPPLY);
    }

    /// @inheritdoc IAuction
    function isGraduated() external view returns (bool) {
        return _isGraduated();
    }

    /// @notice Whether the auction has graduated as of the given checkpoint
    /// @dev The auction is considered `graudated` if the currency raised is greater than or equal to the required currency raised
    function _isGraduated() internal view returns (bool) {
        return $currencyRaisedQ96_X7.gte(REQUIRED_CURRENCY_RAISED_Q96_X7);
    }

    /// @inheritdoc IAuction
    function currencyRaised() external view returns (uint256) {
        return _currencyRaised();
    }

    /// @notice Return the currency raised in uint256 representation
    /// @return The currency raised
    function _currencyRaised() internal view returns (uint256) {
        return $currencyRaisedQ96_X7.divUint256(FixedPoint96.Q96).scaleDownToUint256();
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
        // Default assume that all demand is strictly above the clearing price
        ValueX7 currencyRaisedQ96_X7_ = ValueX7.wrap($sumCurrencyDemandAboveClearingQ96 * deltaMps);

        // There is a special case where the clearing price is at a tick boundary with bids.
        if (_checkpoint.clearingPrice % TICK_SPACING == 0) {
            uint256 currencyDemandAtClearingPriceTickQ96 = _getTick(_checkpoint.clearingPrice).currencyDemandQ96;
            // If there is demand at the clearing price tick, we have to explicitly track the supply sold to that price since they are "partially filled"
            if (currencyDemandAtClearingPriceTickQ96 > 0) {
                // Cache the previous value on the stack to avoid recalculating it
                ValueX7 currencyRaisedAboveClearingPriceQ96_X7 = currencyRaisedQ96_X7_;

                // Get the expected currencyRaised at the rounded up clearing price
                // This uses the rounded up clearing price so this may be higher than the actual amount.
                ValueX7 currencyRaisedQ96RoundedUp_X7 =
                    ValueX7.wrap(TOTAL_SUPPLY).mulUint256(_checkpoint.clearingPrice * deltaMps);

                // We separate all active bids into two groups: those above the clearing price tick and those at the tick
                // There are two ways to derive the currencyRaised at the clearing price tick, either by subtracting
                // the demand above the clearing price from the _total_ currency raised found above, OR
                // by using the currencyDemand at the tick multiplied by the clearing price.
                // If the clearing price is not rounded up, then both methods will give the same result.

                // We subtract the currency raised above the clearing price from the total currency raised
                ValueX7 demandAtClearingPriceQ96_X7 =
                    currencyRaisedQ96RoundedUp_X7.sub(currencyRaisedAboveClearingPriceQ96_X7);

                // Then we determine the currency raised from the demand at the tick using the clearing price
                ValueX7 expectedCurrencyRaisedAtClearingPriceTickQ96_X7 =
                    ValueX7.wrap(currencyDemandAtClearingPriceTickQ96 * deltaMps);

                // The usual case is that `demandAtClearingPriceQ96_X7` is >= to `expectedCurrencyRaisedAtClearingPriceTickQ96_X7`.
                // That means that the demand at the clearing price is >= the amount of currency we expect to raise,
                // which intuitively makes sense since these bidders are being partailly filled.
                // There is more demand at the price than supply remaining to sell.

                // Conversely, if `expectedCurrencyRaisedAtClearingPriceTickQ96_X7` is less than `demandAtClearingPriceQ96_X7`,
                // then the amount of currency we expect to raise from bids at clearing price is greater
                // than the actual demand at clearing price which is incorrect for a partial fill.
                // This means that we had rounded up in the clearing price and the real clearing price is lower.
                // So everyone is fully filled and we use the smaller of the two values which represents the demand at the clearing price.
                ValueX7 currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(
                    FixedPointMathLib.min(
                        ValueX7.unwrap(demandAtClearingPriceQ96_X7),
                        ValueX7.unwrap(expectedCurrencyRaisedAtClearingPriceTickQ96_X7)
                    )
                );

                // We can now recompute the actual currency raised by adding the currency raised from the clearing price and above
                currencyRaisedQ96_X7_ = currencyRaisedAtClearingPriceQ96_X7.add(currencyRaisedAboveClearingPriceQ96_X7);
                // Finally update the cumulative currency raised at this clearing price
                _checkpoint.currencyRaisedAtClearingPriceQ96_X7 =
                    _checkpoint.currencyRaisedAtClearingPriceQ96_X7.add(currencyRaisedAtClearingPriceQ96_X7);
            }
        }

        // Update the global tokens cleared tracked value, rounding up such that some dust is left over after `sweepUnsoldTokens()`
        // note that this still uses the rounded up clearing price in the denominator, so the result can bias lower
        $totalClearedQ96_X7 = $totalClearedQ96_X7.add(
            currencyRaisedQ96_X7_.wrapAndFullMulDivUp(FixedPoint96.Q96, _checkpoint.clearingPrice)
        );
        // Update the global currency raised tracked value
        $currencyRaisedQ96_X7 = $currencyRaisedQ96_X7.add(currencyRaisedQ96_X7_);

        _checkpoint.cumulativeMps += deltaMps;
        // Calculate the harmonic mean of the mps and price (the sum of mps/price)
        // This uses the rounded up clearing price so fully filled bids purchase less tokens for higher prices
        _checkpoint.cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(deltaMps, _checkpoint.clearingPrice);
        return _checkpoint;
    }

    /// @notice Fast forward to the start of the current step and return the number of `mps` sold since the last checkpoint
    /// @param _blockNumber The current block number
    /// @param _lastCheckpointedBlock The block number of the last checkpointed block
    /// @return step The current step in the auction which contains `_blockNumber`
    /// @return deltaMps The number of `mps` sold between the last checkpointed block and the start of the current step
    function _advanceToStartOfCurrentStep(uint64 _blockNumber, uint64 _lastCheckpointedBlock)
        internal
        returns (AuctionStep memory step, uint24 deltaMps)
    {
        // Advance the current step until the current block is within the step
        // Start at the larger of the last checkpointed block or the start block of the current step
        step = $step;
        uint64 start = uint64(FixedPointMathLib.max(step.startBlock, _lastCheckpointedBlock));
        uint64 end = step.endBlock;

        uint24 mps = step.mps;
        while (_blockNumber > end) {
            uint64 blockDelta = end - start;
            unchecked {
                deltaMps += uint24(blockDelta * mps);
            }
            start = end;
            if (end == END_BLOCK) break;
            step = _advanceStep();
            mps = step.mps;
            end = step.endBlock;
        }
    }

    /// @notice Iterate to find the tick where the total demand at and above it is strictly less than the remaining supply in the auction
    /// @dev If the loop reaches the highest tick in the book, `nextActiveTickPrice` will be set to MAX_TICK_PTR
    /// @param _checkpoint The latest checkpoint
    /// @return The new clearing price
    function _iterateOverTicksAndFindClearingPrice(Checkpoint memory _checkpoint) internal returns (uint256) {
        // The clearing price can never be lower than the last checkpoint.
        // If the clearing price is zero, set it to the floor price
        uint256 minimumClearingPrice = _checkpoint.clearingPrice.coalesce(FLOOR_PRICE);
        // If there are no more remaining mps in the auction, we don't need to iterate over ticks
        // and we can return the minimum clearing price above
        if (_checkpoint.remainingMpsInAuction() == 0) {
            return minimumClearingPrice;
        }

        // Place state variables on the stack to save gas
        bool updateStateVariables;
        uint256 sumCurrencyDemandAboveClearingQ96_ = $sumCurrencyDemandAboveClearingQ96;
        uint256 nextActiveTickPrice_ = $nextActiveTickPrice;

        /**
         * We have the current demand above the clearing price, and we want to see if it is enough to fully purchase
         * all of the remaining supply being sold at the nextActiveTickPrice. We only need to check `nextActiveTickPrice`
         * because we know that there are no bids in between the current clearing price and that price.
         *
         * Observe that we need a certain amount of collective demand to increase the auction from the floor price.
         * - This is equal to `totalSupply * floorPrice`
         *
         * If the auction was fully subscribed in the first block which it was active, then the total CURRENCY REQUIRED
         * at any given price is equal to totalSupply * p', where p' is that price.
         */
        uint256 clearingPrice = sumCurrencyDemandAboveClearingQ96_.divUp(TOTAL_SUPPLY);
        while (
            // Loop while the currency amount above the clearing price is greater than the required currency at `nextActiveTickPrice_`
            (nextActiveTickPrice_ != MAX_TICK_PTR
                    && sumCurrencyDemandAboveClearingQ96_ >= TOTAL_SUPPLY * nextActiveTickPrice_)
                // If the demand above clearing rounds up to the `nextActiveTickPrice`, we need to keep iterating over ticks
                // This ensures that the `nextActiveTickPrice` is always the next initialized tick strictly above the clearing price
                || clearingPrice == nextActiveTickPrice_
        ) {
            Tick storage $nextActiveTick = _getTick(nextActiveTickPrice_);
            // Subtract the demand at the current nextActiveTick from the total demand
            sumCurrencyDemandAboveClearingQ96_ -= $nextActiveTick.currencyDemandQ96;
            // Save the previous next active tick price
            minimumClearingPrice = nextActiveTickPrice_;
            // Advance to the next tick
            nextActiveTickPrice_ = $nextActiveTick.next;
            clearingPrice = sumCurrencyDemandAboveClearingQ96_.divUp(TOTAL_SUPPLY);
            updateStateVariables = true;
        }
        // Set the values into storage if we found a new next active tick price
        if (updateStateVariables) {
            $sumCurrencyDemandAboveClearingQ96 = sumCurrencyDemandAboveClearingQ96_;
            $nextActiveTickPrice = nextActiveTickPrice_;
            emit NextActiveTickUpdated(nextActiveTickPrice_);
        }

        // The minimum clearing price is either the floor price or the last tick we iterated over.
        // With the exception of the first iteration, the minimum price is a lower bound on the clearing price
        // because we already verified that we had enough demand to purchase all of the remaining supply at that price.
        if (clearingPrice < minimumClearingPrice) {
            return minimumClearingPrice;
        }
        // Otherwise, return the calculated clearing price
        else {
            return clearingPrice;
        }
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @dev This updates the state of the auction accounting for the bids placed after the last checkpoint
    ///      Checkpoints are created at the top of each block with a new bid and does NOT include that bid
    ///      Because of this, we need to calculate what the new state of the Auction should be before updating
    ///      purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingQ96` value
    /// @param blockNumber The block number to checkpoint at
    function _checkpointAtBlock(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        uint64 lastCheckpointedBlock = $lastCheckpointedBlock;
        if (blockNumber == lastCheckpointedBlock) return latestCheckpoint();

        _checkpoint = latestCheckpoint();
        uint256 clearingPrice = _iterateOverTicksAndFindClearingPrice(_checkpoint);
        if (clearingPrice != _checkpoint.clearingPrice) {
            // Set the new clearing price
            _checkpoint.clearingPrice = clearingPrice;
            // Reset the currencyRaisedAtClearingPrice to zero since the clearing price has changed
            _checkpoint.currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(0);
            emit ClearingPriceUpdated(blockNumber, clearingPrice);
        }

        // Calculate the percentage of the supply that has been sold since the last checkpoint and the start of the current step
        (AuctionStep memory step, uint24 deltaMps) = _advanceToStartOfCurrentStep(blockNumber, lastCheckpointedBlock);
        // `deltaMps` above is equal to the percentage of tokens sold up until the start of the current step.
        // If the last checkpointed block is more recent than the start of the current step, account for the percentage
        // sold since the last checkpointed block. Otherwise, add the percent sold since the start of the current step.
        uint64 blockDelta = blockNumber - uint64(FixedPointMathLib.max(step.startBlock, lastCheckpointedBlock));
        unchecked {
            deltaMps += uint24(blockDelta * step.mps);
        }

        // Sell the percentage of outstanding tokens since the last checkpoint at the current clearing price
        _checkpoint = _sellTokensAtClearingPrice(_checkpoint, deltaMps);
        // Insert the checkpoint into storage, updating latest pointer and the linked list
        _insertCheckpoint(_checkpoint, blockNumber);

        emit CheckpointUpdated(blockNumber, _checkpoint.clearingPrice, _checkpoint.cumulativeMps);
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory) {
        return _checkpointAtBlock(END_BLOCK);
    }

    /// @notice Internal function for bid submission
    /// @dev Validates `maxPrice`, calls the validation hook (if set) and updates global state variables
    ///      For gas efficiency, `prevTickPrice` should be the price of the tick immediately before `maxPrice`.
    /// @dev Does not check that the actual value `amount` was received by the contract
    /// @return bidId The id of the created bid
    function _submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        internal
        returns (uint256 bidId)
    {
        // Reject bids which would cause TOTAL_SUPPLY * maxPrice to overflow a uint256
        if (maxPrice > MAX_BID_PRICE) revert InvalidBidPriceTooHigh();

        // Get the latest checkpoint before validating the bid
        Checkpoint memory _checkpoint = checkpoint();
        // Revert if there are no more tokens to be sold
        if (_checkpoint.remainingMpsInAuction() == 0) revert AuctionSoldOut();
        // We don't allow bids to be submitted at or below the clearing price
        if (maxPrice <= _checkpoint.clearingPrice) revert BidMustBeAboveClearingPrice();

        // Initialize the tick if needed. This will no-op if the tick is already initialized.
        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        // Call the validation hook and bubble up the revert reason if it reverts
        VALIDATION_HOOK.handleValidate(maxPrice, amount, owner, msg.sender, hookData);

        Bid memory bid;
        uint256 amountQ96 = uint256(amount) << FixedPoint96.RESOLUTION;
        (bid, bidId) = _createBid(amountQ96, owner, maxPrice, _checkpoint.cumulativeMps);

        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        uint256 bidEffectiveAmountQ96 = bid.toEffectiveAmount();
        // Update the tick demand with the bid's scaled amount
        _updateTickDemand(maxPrice, bidEffectiveAmountQ96);
        // Update the global sum of currency demand above the clearing price tracker
        // Per the validation checks above this bid must be above the clearing price
        $sumCurrencyDemandAboveClearingQ96 += bidEffectiveAmountQ96;

        // If the sum of demand above clearing price becomes large enough to overflow a multiplication an X7 value,
        // revert to prevent the bid from being submitted.
        if ($sumCurrencyDemandAboveClearingQ96 >= ConstantsLib.X7_UPPER_BOUND) {
            revert InvalidBidUnableToClear();
        }

        emit BidSubmitted(bidId, owner, maxPrice, amount);
    }

    /// @notice Internal function for processing the exit of a bid
    /// @dev Given a bid, tokens filled and refund, process the transfers and refund
    ///      `exitedBlock` MUST be checked by the caller to prevent double spending
    /// @param bidId The id of the bid to exit
    /// @param tokensFilled The number of tokens filled
    /// @param currencySpentQ96 The amount of currency the bid spent
    function _processExit(uint256 bidId, uint256 tokensFilled, uint256 currencySpentQ96) internal {
        Bid storage $bid = _getBid(bidId);
        address _owner = $bid.owner;

        uint256 refund = ($bid.amountQ96 - currencySpentQ96) >> FixedPoint96.RESOLUTION;

        $bid.tokensFilled = tokensFilled;
        $bid.exitedBlock = uint64(block.number);

        if (refund > 0) {
            CURRENCY.transfer(_owner, refund);
        }

        emit BidExited(bidId, _owner, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function checkpoint() public onlyActiveAuction returns (Checkpoint memory) {
        if (block.number > END_BLOCK) {
            return _getFinalCheckpoint();
        } else {
            return _checkpointAtBlock(uint64(block.number));
        }
    }

    /// @inheritdoc IAuction
    /// @dev Bids can be submitted anytime between the startBlock and the endBlock.
    function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        public
        payable
        onlyActiveAuction
        returns (uint256)
    {
        // Bids cannot be submitted at the endBlock or after
        if (block.number >= END_BLOCK) revert AuctionIsOver();
        if (owner == address(0)) revert BidOwnerCannotBeZeroAddress();
        if (CURRENCY.isAddressZero()) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert CurrencyIsNotNative();
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(CURRENCY), msg.sender, address(this), amount);
        }
        return _submitBid(maxPrice, amount, owner, prevTickPrice, hookData);
    }

    /// @inheritdoc IAuction
    /// @dev The call to `submitBid` checks `onlyActiveAuction` so it's not required on this function
    function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
        external
        payable
        returns (uint256)
    {
        return submitBid(maxPrice, amount, owner, FLOOR_PRICE, hookData);
    }

    /// @inheritdoc IAuction
    function exitBid(uint256 bidId) external onlyAfterAuctionIsOver {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        if (!_isGraduated()) {
            // In the case that the auction did not graduate, fully refund the bid
            return _processExit(bidId, 0, 0);
        }
        // Only bids with a max price strictly above the final clearing price can be exited via `exitBid`
        if (bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();

        // Account for the fully filled checkpoints
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        (uint256 tokensFilled, uint256 currencySpentQ96) =
            _accountFullyFilledCheckpoints(finalCheckpoint, startCheckpoint, bid);

        _processExit(bidId, tokensFilled, currencySpentQ96);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 outbidBlock) external {
        // Checkpoint before checking any of the hints because they could depend on the latest checkpoint
        Checkpoint memory currentBlockCheckpoint = checkpoint();

        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        // Prevent bids from being exited before graduation
        if (!_isGraduated()) {
            if (block.number >= END_BLOCK) {
                // If the auction is over, fully refund the bid
                return _processExit(bidId, 0, 0);
            }
            revert CannotPartiallyExitBidBeforeGraduation();
        }

        uint256 bidMaxPrice = bid.maxPrice;
        uint64 bidStartBlock = bid.startBlock;

        // Get the last fully filled checkpoint from the user's provided hint
        Checkpoint memory lastFullyFilledCheckpoint = _getCheckpoint(lastFullyFilledCheckpointBlock);
        // Since `lastFullyFilledCheckpointBlock` points to the last fully filled Checkpoint, it must be < bid.maxPrice
        // The next Checkpoint after `lastFullyFilledCheckpoint` must be partially or fully filled (clearingPrice >= bid.maxPrice)
        // `lastFullyFilledCheckpoint` also cannot be before the bid's startCheckpoint
        if (
            lastFullyFilledCheckpoint.clearingPrice >= bidMaxPrice
                || _getCheckpoint(lastFullyFilledCheckpoint.next).clearingPrice < bidMaxPrice
                || lastFullyFilledCheckpointBlock < bidStartBlock
        ) {
            revert InvalidLastFullyFilledCheckpointHint();
        }

        // There is guaranteed to be a checkpoint at the bid's startBlock because we always checkpoint before bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bidStartBlock);

        // Intitialize the tokens filled and currency spent trackers
        uint256 tokensFilled;
        uint256 currencySpentQ96;

        // If the lastFullyFilledCheckpoint is provided, account for the fully filled checkpoints
        if (lastFullyFilledCheckpoint.clearingPrice > 0) {
            // Assign the calculated tokens filled and currency spent to `tokensFilled` and `currencySpentQ96`
            (tokensFilled, currencySpentQ96) =
                _accountFullyFilledCheckpoints(lastFullyFilledCheckpoint, startCheckpoint, bid);
        }

        // Upper checkpoint is the last checkpoint where the bid is partially filled
        Checkpoint memory upperCheckpoint;
        // If outbidBlock is not zero, the bid was outbid and the bidder is requesting an early exit
        // This can be done before the auction's endBlock
        if (outbidBlock != 0) {
            // If the provided hint is the current block, use the checkpoint returned by `checkpoint()` instead of getting it from storage
            Checkpoint memory outbidCheckpoint;
            if (outbidBlock == block.number) {
                outbidCheckpoint = currentBlockCheckpoint;
            } else {
                outbidCheckpoint = _getCheckpoint(outbidBlock);
            }

            upperCheckpoint = _getCheckpoint(outbidCheckpoint.prev);
            // We require that the outbid checkpoint is > bid max price AND the checkpoint before it is <= bid max price, revert if either of these conditions are not met
            if (outbidCheckpoint.clearingPrice <= bidMaxPrice || upperCheckpoint.clearingPrice > bidMaxPrice) {
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
            if (upperCheckpoint.clearingPrice != bidMaxPrice) {
                revert CannotExitBid();
            }
        }

        // If there is an `upperCheckpoint` that means that the bid had a period where it was partially filled
        // From the logic above, `upperCheckpoint` now points to the last checkpoint where the clearingPrice == bidMaxPrice.
        // Because the clearing price can never decrease between checkpoints, and the fact that you cannot enter a bid
        // at or below the current clearing price, the bid MUST have been active during the entire partial fill period.
        // And `upperCheckpoint` tracks the cumulative currency raised at that clearing price since the first partially filled checkpoint.
        if (upperCheckpoint.clearingPrice == bidMaxPrice) {
            uint256 tickDemandQ96 = _getTick(bidMaxPrice).currencyDemandQ96;
            (uint256 partialTokensFilled, uint256 partialCurrencySpentQ96) = _accountPartiallyFilledCheckpoints(
                bid, tickDemandQ96, upperCheckpoint.currencyRaisedAtClearingPriceQ96_X7
            );
            // Add the tokensFilled and currencySpentQ96 from the partially filled checkpoints to the total
            tokensFilled += partialTokensFilled;
            currencySpentQ96 += partialCurrencySpentQ96;
        }

        _processExit(bidId, tokensFilled, currencySpentQ96);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 _bidId) external onlyAfterClaimBlock ensureEndBlockIsCheckpointed {
        // Tokens cannot be claimed if the auction did not graduate
        if (!_isGraduated()) revert NotGraduated();

        (address owner, uint256 tokensFilled) = _internalClaimTokens(_bidId);

        if (tokensFilled > 0) {
            Currency.wrap(address(TOKEN)).transfer(owner, tokensFilled);
            emit TokensClaimed(_bidId, owner, tokensFilled);
        }
    }

    /// @inheritdoc IAuction
    function claimTokensBatch(address _owner, uint256[] calldata _bidIds)
        external
        onlyAfterClaimBlock
        ensureEndBlockIsCheckpointed
    {
        // Tokens cannot be claimed if the auction did not graduate
        if (!_isGraduated()) revert NotGraduated();

        uint256 tokensFilled = 0;
        for (uint256 i = 0; i < _bidIds.length; i++) {
            (address bidOwner, uint256 bidTokensFilled) = _internalClaimTokens(_bidIds[i]);

            if (bidOwner != _owner) {
                revert BatchClaimDifferentOwner(_owner, bidOwner);
            }

            tokensFilled += bidTokensFilled;

            if (bidTokensFilled > 0) {
                emit TokensClaimed(_bidIds[i], bidOwner, bidTokensFilled);
            }
        }

        if (tokensFilled > 0) {
            Currency.wrap(address(TOKEN)).transfer(_owner, tokensFilled);
        }
    }

    /// @notice Internal function to claim tokens for a single bid
    /// @param bidId The id of the bid
    /// @return owner The owner of the bid
    /// @return tokensFilled The amount of tokens filled
    function _internalClaimTokens(uint256 bidId) internal returns (address owner, uint256 tokensFilled) {
        Bid storage $bid = _getBid(bidId);
        if ($bid.exitedBlock == 0) revert BidNotExited();

        // Set return values
        owner = $bid.owner;
        tokensFilled = $bid.tokensFilled;

        // Set the tokens filled to 0
        $bid.tokensFilled = 0;
    }

    /// @inheritdoc IAuction
    function sweepCurrency() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed {
        // Cannot sweep if already swept
        if (sweepCurrencyBlock != 0) revert CannotSweepCurrency();
        // Cannot sweep currency if the auction has not graduated, as all of the Currency must be refunded
        if (!_isGraduated()) revert NotGraduated();
        _sweepCurrency(_currencyRaised());
    }

    /// @inheritdoc IAuction
    function sweepUnsoldTokens() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed {
        if (sweepUnsoldTokensBlock != 0) revert CannotSweepTokens();
        uint256 unsoldTokens;
        if (_isGraduated()) {
            unsoldTokens = TOTAL_SUPPLY_Q96.scaleUpToX7().sub($totalClearedQ96_X7).divUint256(FixedPoint96.Q96)
                .scaleDownToUint256();
        } else {
            unsoldTokens = TOTAL_SUPPLY;
        }
        _sweepUnsoldTokens(unsoldTokens);
    }

    // Getters
    /// @inheritdoc IAuction
    function claimBlock() external view returns (uint64) {
        return CLAIM_BLOCK;
    }

    /// @inheritdoc IAuction
    function validationHook() external view returns (IValidationHook) {
        return VALIDATION_HOOK;
    }

    /// @inheritdoc IAuction
    function currencyRaisedQ96_X7() external view returns (ValueX7) {
        return $currencyRaisedQ96_X7;
    }

    /// @inheritdoc IAuction
    function sumCurrencyDemandAboveClearingQ96() external view returns (uint256) {
        return $sumCurrencyDemandAboveClearingQ96;
    }

    /// @inheritdoc IAuction
    function totalClearedQ96_X7() external view returns (ValueX7) {
        return $totalClearedQ96_X7;
    }

    /// @inheritdoc IAuction
    function totalCleared() external view returns (uint256) {
        return $totalClearedQ96_X7.divUint256(FixedPoint96.Q96).scaleDownToUint256();
    }
}
