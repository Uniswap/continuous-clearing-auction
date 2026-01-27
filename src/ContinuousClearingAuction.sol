// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {StepStorage} from './StepStorage.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {TokenCurrencyStorage} from './TokenCurrencyStorage.sol';
import {AuctionParameters, IContinuousClearingAuction} from './interfaces/IContinuousClearingAuction.sol';
import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {ILBPInitializer, LBPInitializationParams} from './interfaces/external/ILBPInitializer.sol';
import {ILBP_INITIALIZER_INTERFACE_ID} from './interfaces/external/ILBPInitializer.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {CheckpointLib} from './libraries/CheckpointLib.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from './libraries/MaxBidPriceLib.sol';
import {AuctionStep, StepLib} from './libraries/StepLib.sol';
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ReentrancyGuardTransient} from 'solady/utils/ReentrancyGuardTransient.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title ContinuousClearingAuction
/// @custom:security-contact security@uniswap.org
/// @notice Implements a time weighted uniform clearing price auction
/// @dev Can be constructed directly or through the ContinuousClearingAuctionFactory. In either case, users must validate
///      that the auction parameters are correct and not incorrectly set.
contract ContinuousClearingAuction is
    BidStorage,
    CheckpointStorage,
    StepStorage,
    TickStorage,
    TokenCurrencyStorage,
    BlockNumberish,
    ReentrancyGuardTransient,
    IContinuousClearingAuction
{
    using FixedPointMathLib for *;
    using CurrencyLibrary for Currency;
    using BidLib for *;
    using StepLib for *;
    using CheckpointLib for Checkpoint;
    using ValidationHookLib for IValidationHook;
    using ValueX7Lib for *;

    /// @notice The maximum price which a bid can be submitted at
    /// @dev Set during construction using MaxBidPriceLib.maxBidPrice() based on TOTAL_SUPPLY
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
    /// @notice The most up to date clearing price, set on each call to `checkpoint`
    /// @dev This can be incremented manually by calling `forceIterateOverTicks`
    uint256 internal $clearingPrice;

    /// @notice Whether the TOTAL_SUPPLY of tokens has been received
    bool private $_tokensReceived;

    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        StepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
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

        // See MaxBidPriceLib library for more details on the bid price calculations.
        MAX_BID_PRICE = MaxBidPriceLib.maxBidPrice(TOTAL_SUPPLY);
        // The floor price and tick spacing must allow for at least one tick above the floor price to be initialized
        if (_parameters.tickSpacing > MAX_BID_PRICE || _parameters.floorPrice > MAX_BID_PRICE - _parameters.tickSpacing)
        {
            revert FloorPriceAndTickSpacingGreaterThanMaxBidPrice(
                _parameters.floorPrice + _parameters.tickSpacing, MAX_BID_PRICE
            );
        }

        $clearingPrice = FLOOR_PRICE;
        emit ClearingPriceUpdated(_getBlockNumberish(), $clearingPrice);
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (_getBlockNumberish() < END_BLOCK) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for claim related functions which can only be called after the claim block
    modifier onlyAfterClaimBlock() {
        if (_getBlockNumberish() < CLAIM_BLOCK) revert NotClaimable();
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
        if (_getBlockNumberish() < START_BLOCK) revert AuctionNotStarted();
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

    /// @inheritdoc ILBPInitializer
    /// @dev The calling contract must be aware that the values returned in this function for `currencyRaised` and `tokensSold`
    ///      may not be reflective of the actual values if the auction did not graduate.
    function lbpInitializationParams() external view returns (LBPInitializationParams memory params) {
        // Require that the auction has been checkpointed at the end block before returning initialization params
        if ($lastCheckpointedBlock != END_BLOCK) revert AuctionIsNotFinalized();

        return LBPInitializationParams({
            initialPriceX96: $clearingPrice, tokensSold: totalCleared(), currencyRaised: currencyRaised()
        });
    }

    /// @inheritdoc IContinuousClearingAuction
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ILBP_INITIALIZER_INTERFACE_ID || interfaceId == IERC165.supportsInterface.selector;
    }

    /// @inheritdoc IContinuousClearingAuction
    function clearingPrice() external view returns (uint256) {
        return $clearingPrice;
    }

    /// @inheritdoc IContinuousClearingAuction
    function isGraduated() external view returns (bool) {
        return _isGraduated();
    }

    /// @notice Whether the auction has graduated as of the given checkpoint
    /// @dev The auction is considered `graudated` if the currency raised is greater than or equal to the required currency raised
    function _isGraduated() internal view returns (bool) {
        return ValueX7.unwrap($currencyRaisedQ96_X7) >= ValueX7.unwrap(REQUIRED_CURRENCY_RAISED_Q96_X7);
    }

    /// @inheritdoc IContinuousClearingAuction
    function currencyRaised() public view returns (uint256) {
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
    /// @param _deltaMps The number of mps to sell
    /// @return The checkpoint with all cumulative values updated
    function _sellTokensAtClearingPrice(Checkpoint memory _checkpoint, uint24 _deltaMps)
        internal
        returns (Checkpoint memory)
    {
        // Advance the auction by selling an additional `deltaMps` share of TOTAL_SUPPLY at the current clearing price.
        //
        // At a high level, the algorithm is:
        // 1) Assume all demand is strictly above the clearing price: currencyRaised = sumAboveClearingQ96 × deltaMps.
        // 2) If the clearing price is exactly on an initialized tick that has demand, account for the partially filled
        //    bids at the clearing tick. There are two ways to derive the at-clearing currencyRaised when the price is
        //    not rounded up:
        //       (A) total implied currencyRaised at the rounded-up price − contribution from above-clearing
        //       (B) tick demand at clearing × deltaMps
        //    If the clearing price was rounded up to the tick boundary, (A) can exceed (B); cap with min(A, B).

        uint256 priceQ96 = _checkpoint.clearingPrice;
        uint256 deltaMpsU = uint256(_deltaMps);
        uint256 sumAboveQ96 = $sumCurrencyDemandAboveClearingQ96;

        // The base case is where all demand sits strictly above the clearing price
        uint256 currencyRaisedDeltaQ96X7;
        unchecked {
            currencyRaisedDeltaQ96X7 = sumAboveQ96 * deltaMpsU; // Overflow prevented by _submitBid::InvalidBidUnableToClear()
        }

        // When the clearing price is a tick with non zero demand
        // bidders at that tick can be partially filled. We split the currencyRaised into:
        // - (1) above-clearing contribution (already computed) and
        // - (2) at-clearing contribution.
        if (priceQ96 % TICK_SPACING == 0) {
            uint256 demandAtPriceQ96 = _getTick(priceQ96).currencyDemandQ96;
            if (demandAtPriceQ96 > 0) {
                // Cache and rename the above-clearing contribution
                uint256 currencyRaisedAboveClearingQ96X7 = currencyRaisedDeltaQ96X7;

                // Total implied currencyRaised at the (potentially rounded-up) clearing price:
                // = TOTAL_SUPPLY × priceQ96 (Q96) × deltaMps (X7) = Q96*X7
                // Note: this will be an overestimate if the price is rounded up
                uint256 totalCurrencyForDeltaQ96X7;
                unchecked {
                    totalCurrencyForDeltaQ96X7 = (uint256(TOTAL_SUPPLY) * priceQ96) * deltaMpsU;
                }

                // (A) Derived contribution from the clearing tick by substracting
                //     the above-clearing contribution from the total implied currencyRaised
                uint256 calculatedCurrencyRaisedAtClearingQ96X7 =
                    totalCurrencyForDeltaQ96X7 - currencyRaisedAboveClearingQ96X7;

                // (B) Maximum possible currencyRaised from bids at the clearing tick, scaling the tick demand by deltaMps
                uint256 maximumCurrencyRaisedAtClearingQ96X7;
                unchecked {
                    maximumCurrencyRaisedAtClearingQ96X7 = demandAtPriceQ96 * deltaMpsU;
                }

                // If price was rounded up, (A) can exceed (B). In that case, currencyRaised from the clearing tick is bounded by actual
                // tick demand; take min((A), (B)). If the price was not rounded up, (A) == (B).
                uint256 currencyRaisedAtClearingQ96X7 = FixedPointMathLib.min(
                    calculatedCurrencyRaisedAtClearingQ96X7, maximumCurrencyRaisedAtClearingQ96X7
                );

                // Change in currency raised = currency raised at clearing + currency raised above clearing
                currencyRaisedDeltaQ96X7 = currencyRaisedAtClearingQ96X7 + currencyRaisedAboveClearingQ96X7;
                // Track cumulative currency raised exactly at this clearing price (used for partial exits)
                _checkpoint.currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(
                    ValueX7.unwrap(_checkpoint.currencyRaisedAtClearingPriceQ96_X7) + currencyRaisedAtClearingQ96X7
                );
            }
        }

        // Convert currency to tokens at price, rounding up, and update global cleared tokens.
        // Intentional round-up leaves a small amount of dust to sweep, ensuring cleared tokens never exceed TOTAL_SUPPLY
        // even when using rounded-up clearing prices on tick boundaries.
        uint256 tokensClearedQ96X7 = currencyRaisedDeltaQ96X7.fullMulDivUp(FixedPoint96.Q96, priceQ96);
        $totalClearedQ96_X7 = ValueX7.wrap(ValueX7.unwrap($totalClearedQ96_X7) + tokensClearedQ96X7);
        // Update global currency raised
        $currencyRaisedQ96_X7 = ValueX7.wrap(ValueX7.unwrap($currencyRaisedQ96_X7) + currencyRaisedDeltaQ96X7);

        _checkpoint.cumulativeMps += _deltaMps;
        // Harmonic-mean accumulator: add (mps / price) using the rounded-up clearing price for this increment
        _checkpoint.cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(_deltaMps, priceQ96);
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
    /// @param _untilTickPrice The tick price to iterate until
    /// @return The new clearing price
    function _iterateOverTicksAndFindClearingPrice(uint256 _untilTickPrice) internal returns (uint256) {
        // The new clearing price can never be lower than the current clearing price
        uint256 minimumClearingPrice = $clearingPrice;

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
        uint256 clearingPrice_ = sumCurrencyDemandAboveClearingQ96_.divUp(TOTAL_SUPPLY);
        while (
            // Loop while the currency amount above the clearing price is greater than the required currency at `nextActiveTickPrice_`
            (nextActiveTickPrice_ != _untilTickPrice
                    && sumCurrencyDemandAboveClearingQ96_ >= TOTAL_SUPPLY * nextActiveTickPrice_)
                // If the demand above clearing rounds up to the `nextActiveTickPrice`, we need to keep iterating over ticks
                // This ensures that the `nextActiveTickPrice` is always the next initialized tick strictly above the clearing price
                || clearingPrice_ == nextActiveTickPrice_
        ) {
            Tick storage $nextActiveTick = _getTick(nextActiveTickPrice_);
            // Subtract the demand at the current nextActiveTick from the total demand
            sumCurrencyDemandAboveClearingQ96_ -= $nextActiveTick.currencyDemandQ96;
            // Save the previous next active tick price
            minimumClearingPrice = nextActiveTickPrice_;
            // Advance to the next tick
            nextActiveTickPrice_ = $nextActiveTick.next;
            clearingPrice_ = sumCurrencyDemandAboveClearingQ96_.divUp(TOTAL_SUPPLY);
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
        if (clearingPrice_ < minimumClearingPrice) {
            return minimumClearingPrice;
        }
        // Otherwise, return the calculated clearing price
        return clearingPrice_;
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @dev This updates the state of the auction accounting for the bids placed after the last checkpoint
    ///      Checkpoints are created at the top of each block with a new bid and does NOT include that bid
    ///      Because of this, we need to calculate what the new state of the Auction should be before updating
    ///      purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingQ96` value
    /// @param _blockNumber The block number to checkpoint at
    function _checkpointAtBlock(uint64 _blockNumber) internal returns (Checkpoint memory _checkpoint) {
        uint64 lastCheckpointedBlock = $lastCheckpointedBlock;
        if (_blockNumber == lastCheckpointedBlock) return latestCheckpoint();

        _checkpoint = latestCheckpoint();

        // If there are no more remaining mps in the auction, we don't need to iterate over ticks
        // Or update the clearing price
        if (_checkpoint.remainingMpsInAuction() > 0) {
            // Iterate over all ticks until MAX_TICK_PTR to find the clearing price
            // This can revert with out of gas if there are a large number of ticks
            uint256 newClearingPrice = _iterateOverTicksAndFindClearingPrice(MAX_TICK_PTR);
            // checkpoint has the stale clearing price
            if (newClearingPrice != _checkpoint.clearingPrice) {
                // Set the new clearing price
                _checkpoint.clearingPrice = newClearingPrice;
                // Reset the currencyRaisedAtClearingPrice to zero since the clearing price has changed
                _checkpoint.currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(0);
                // Write the new cleraing price to storage
                $clearingPrice = newClearingPrice;
                emit ClearingPriceUpdated(_blockNumber, newClearingPrice);
            }
        }

        // Calculate the percentage of the supply that has been sold since the last checkpoint and the start of the current step
        (AuctionStep memory step, uint24 deltaMps) = _advanceToStartOfCurrentStep(_blockNumber, lastCheckpointedBlock);
        // `deltaMps` above is equal to the percentage of tokens sold up until the start of the current step.
        // If the last checkpointed block is more recent than the start of the current step, account for the percentage
        // sold since the last checkpointed block. Otherwise, add the percent sold since the start of the current step.
        uint64 blockDelta = _blockNumber - uint64(FixedPointMathLib.max(step.startBlock, lastCheckpointedBlock));
        unchecked {
            deltaMps += uint24(blockDelta * step.mps);
        }

        // Sell the percentage of outstanding tokens since the last checkpoint at the current clearing price
        _checkpoint = _sellTokensAtClearingPrice(_checkpoint, deltaMps);
        // Insert the checkpoint into storage, updating latest pointer and the linked list
        _insertCheckpoint(_checkpoint, _blockNumber);

        emit CheckpointUpdated(_blockNumber, _checkpoint.clearingPrice, _checkpoint.cumulativeMps);
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over
    function _getFinalCheckpoint() internal returns (Checkpoint memory) {
        return _checkpointAtBlock(END_BLOCK);
    }

    /// @notice Internal function for bid submission
    /// @dev Validates `maxPrice`, calls the validation hook (if set) and updates global state variables
    ///      For gas efficiency, `prevTickPrice` should be the price of the tick immediately before `maxPrice`.
    /// @dev Implementing functions must check that the actual value `amount` is received by the contract
    /// @return bidId The id of the created bid
    function _submitBid(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        uint256 _prevTickPrice,
        bytes calldata _hookData
    ) internal returns (uint256 bidId) {
        // Reject bids which would cause TOTAL_SUPPLY * maxPrice to overflow a uint256
        if (_maxPrice > MAX_BID_PRICE) revert InvalidBidPriceTooHigh(_maxPrice, MAX_BID_PRICE);

        // Call the validation hook and bubble up the revert reason if it reverts
        VALIDATION_HOOK.handleValidate(_maxPrice, _amount, _owner, msg.sender, _hookData);

        // Get the latest checkpoint before validating the bid
        uint64 currentBlockNumberIsh = uint64(_getBlockNumberish());
        Checkpoint memory _checkpoint = _checkpointAtBlock(currentBlockNumberIsh);
        // Revert if there are no more tokens to be sold
        if (_checkpoint.remainingMpsInAuction() == 0) revert AuctionSoldOut();
        // We don't allow bids to be submitted at or below the clearing price
        if (_maxPrice <= $clearingPrice) revert BidMustBeAboveClearingPrice();

        // Initialize the tick if needed. This will no-op if the tick is already initialized.
        _initializeTickIfNeeded(_prevTickPrice, _maxPrice);

        Bid memory bid;
        uint256 amountQ96 = uint256(_amount) << FixedPoint96.RESOLUTION;
        (bid, bidId) = _createBid(currentBlockNumberIsh, amountQ96, _owner, _maxPrice, _checkpoint.cumulativeMps);

        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        uint256 bidEffectiveAmountQ96 = bid.toEffectiveAmount();
        // Update the tick demand with the bid's scaled amount
        _updateTickDemand(_maxPrice, bidEffectiveAmountQ96);
        // Update the global sum of currency demand above the clearing price tracker
        // Per the validation checks above this bid must be above the clearing price
        $sumCurrencyDemandAboveClearingQ96 += bidEffectiveAmountQ96;

        // If the sum of demand above clearing price becomes large enough to overflow a multiplication an X7 value,
        // revert to prevent the bid from being submitted.
        if ($sumCurrencyDemandAboveClearingQ96 >= ConstantsLib.X7_UPPER_BOUND) {
            revert InvalidBidUnableToClear();
        }

        emit BidSubmitted(bidId, _owner, _maxPrice, _amount);
    }

    /// @notice Internal function for processing the exit of a bid
    /// @dev Given a bid, tokens filled and refund, process the transfers and refund
    ///      `exitedBlock` MUST be checked by the caller to prevent double spending
    /// @param _bidId The id of the bid to exit
    /// @param _tokensFilled The number of tokens filled
    /// @param _currencySpentQ96 The amount of currency the bid spent
    function _processExit(uint256 _bidId, uint256 _tokensFilled, uint256 _currencySpentQ96) internal {
        Bid storage $bid = _getBid(_bidId);
        address owner = $bid.owner;

        uint256 bidAmountQ96 = $bid.amountQ96;
        // In edge cases where a bid spends all of its currency across fully filled and partially filled checkpoints,
        // the sum of currencySpent can be rounded up to one wei more than the bid amount. We clamp the refund to the bid amount.
        uint256 refund = FixedPointMathLib.saturatingSub(bidAmountQ96, _currencySpentQ96) >> FixedPoint96.RESOLUTION;

        $bid.tokensFilled = _tokensFilled;
        $bid.exitedBlock = uint64(_getBlockNumberish());

        if (refund > 0) {
            CURRENCY.transfer(owner, refund);
        }

        emit BidExited(_bidId, owner, _tokensFilled, refund);
    }

    /// @inheritdoc IContinuousClearingAuction
    function checkpoint() public onlyActiveAuction returns (Checkpoint memory) {
        uint64 currentBlockNumberIsh = uint64(_getBlockNumberish());
        if (currentBlockNumberIsh > END_BLOCK) {
            return _getFinalCheckpoint();
        } else {
            return _checkpointAtBlock(currentBlockNumberIsh);
        }
    }

    /// @notice Manually iterate over ticks to update the clearing price
    /// @dev This is used to prevent DoS attacks which initialize a large number of ticks
    /// @param _untilTickPrice The tick price to iterate until
    function forceIterateOverTicks(uint256 _untilTickPrice) external onlyActiveAuction nonReentrant returns (uint256) {
        if (_untilTickPrice != MAX_TICK_PTR) {
            // Ensure that the price is at a tick boundary
            Tick storage $tick = _getTick(_untilTickPrice);
            // The tick must be initialized otherwise it will be an infinite loop
            if ($tick.next == 0) revert TickNotInitialized();
            // The untilTickPrice must be greater than the current next active tick price
            if (_untilTickPrice <= $nextActiveTickPrice) {
                revert TickHintMustBeGreaterThanNextActiveTickPrice(_untilTickPrice, $nextActiveTickPrice);
            }
        }
        uint256 newClearingPrice = _iterateOverTicksAndFindClearingPrice(_untilTickPrice);
        // Update the clearing price in storage if it has changed
        if (newClearingPrice != $clearingPrice) {
            $clearingPrice = newClearingPrice;
            emit ClearingPriceUpdated(_getBlockNumberish(), newClearingPrice);
        }
        return newClearingPrice;
    }

    /// @inheritdoc IContinuousClearingAuction
    /// @dev Bids can be submitted anytime between the startBlock and the endBlock.
    function submitBid(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        uint256 _prevTickPrice,
        bytes calldata _hookData
    ) public payable onlyActiveAuction nonReentrant returns (uint256) {
        // Bids cannot be submitted at the endBlock or after
        if (_getBlockNumberish() >= END_BLOCK) revert AuctionIsOver();
        if (_amount == 0) revert BidAmountTooSmall();
        if (_owner == address(0)) revert BidOwnerCannotBeZeroAddress();
        if (CURRENCY.isAddressZero()) {
            if (msg.value != _amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert CurrencyIsNotNative();
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(CURRENCY), msg.sender, address(this), _amount);
        }
        return _submitBid(_maxPrice, _amount, _owner, _prevTickPrice, _hookData);
    }

    /// @inheritdoc IContinuousClearingAuction
    /// @dev The call to `submitBid` checks `onlyActiveAuction` so it's not required on this function
    function submitBid(uint256 _maxPrice, uint128 _amount, address _owner, bytes calldata _hookData)
        external
        payable
        returns (uint256)
    {
        return submitBid(_maxPrice, _amount, _owner, FLOOR_PRICE, _hookData);
    }

    /// @inheritdoc IContinuousClearingAuction
    function exitBid(uint256 _bidId) external onlyAfterAuctionIsOver {
        Bid memory bid = _getBid(_bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        if (!_isGraduated()) {
            // Fully refund the bid if the auction did not graduate, since it is over
            return _processExit(_bidId, 0, 0);
        }
        // Only bids with a maxPrice strictly above the final clearing price can be exited in this function
        if (bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();

        // Calculate the tokens and currency spent from the fully filled checkpoints
        (uint256 tokensFilled, uint256 currencySpentQ96) =
            _accountFullyFilledCheckpoints(finalCheckpoint, _getCheckpoint(bid.startBlock), bid);

        _processExit(_bidId, tokensFilled, currencySpentQ96);
    }

    /// @inheritdoc IContinuousClearingAuction
    function exitPartiallyFilledBid(uint256 _bidId, uint64 _lastFullyFilledCheckpointBlock, uint64 _outbidBlock)
        external
    {
        // Checkpoint first as the validity of the hints depend on the latest state
        Checkpoint memory currentBlockCheckpoint = checkpoint();
        // Cache the current block number
        uint256 currentBlockNumberIsh = _getBlockNumberish();

        Bid memory bid = _getBid(_bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        // Prevent bids from being exited before graduation
        if (!_isGraduated()) {
            if (currentBlockNumberIsh >= END_BLOCK) {
                // If the auction is over, fully refund the bid
                return _processExit(_bidId, 0, 0);
            }
            revert CannotPartiallyExitBidBeforeGraduation();
        }

        uint256 bidMaxPrice = bid.maxPrice;
        uint64 bidStartBlock = bid.startBlock;

        Checkpoint memory lastFullyFilledCheckpoint = _getCheckpoint(_lastFullyFilledCheckpointBlock);
        // Since `lastFullyFilledCheckpointBlock` must be the last fully filled Checkpoint, it must be < bid.maxPrice
        // And the bid must be partially filled or outbid (clearingPrice >= bid.maxPrice) in the next Checkpoint.
        // `lastFullyFilledCheckpoint` MUST be at least the bid's startCheckpoint since new bids must be at or above the current clearing price.
        if (
            lastFullyFilledCheckpoint.clearingPrice >= bidMaxPrice
                || _getCheckpoint(lastFullyFilledCheckpoint.next).clearingPrice < bidMaxPrice
                || _lastFullyFilledCheckpointBlock < bidStartBlock
        ) {
            revert InvalidLastFullyFilledCheckpointHint();
        }

        // Calculate the tokens and currency spent for the fully filled checkpoints
        // If the bid is outbid in the same block it is submitted in, these two checkpoints will be identical.
        // The extra gas to check for this isn't worth it since the returned values will be 0.
        (uint256 tokensFilled, uint256 currencySpentQ96) =
            _accountFullyFilledCheckpoints(lastFullyFilledCheckpoint, _getCheckpoint(bidStartBlock), bid);

        // Upper checkpoint is the last checkpoint where the bid is partially filled
        Checkpoint memory upperCheckpoint;
        // If outbidBlock is not zero, the bid was outbid and the bidder is requesting an early exit before the end of the auction
        if (_outbidBlock != 0) {
            // If the provided hint is the current block, use the checkpoint on the stack instead of getting it from storage
            Checkpoint memory outbidCheckpoint;
            if (_outbidBlock == currentBlockNumberIsh) {
                outbidCheckpoint = currentBlockCheckpoint;
            } else {
                outbidCheckpoint = _getCheckpoint(_outbidBlock);
            }

            upperCheckpoint = _getCheckpoint(outbidCheckpoint.prev);
            // We require that the outbid checkpoint is > bid max price AND the checkpoint before it is <= bid max price, revert if either of these conditions are not met
            if (outbidCheckpoint.clearingPrice <= bidMaxPrice || upperCheckpoint.clearingPrice > bidMaxPrice) {
                revert InvalidOutbidBlockCheckpointHint();
            }
        } else {
            // The only other valid partial exit case is if the final clearing price is equal to the bid's maxPrice.
            // These bids can only be exited after the auction ends
            if (currentBlockNumberIsh < END_BLOCK) revert CannotPartiallyExitBidBeforeEndBlock();
            // Set the upper checkpoint to the current checkpoint, which is also the final checkpoint since we already validated that the auction is over
            upperCheckpoint = currentBlockCheckpoint;
            // Revert if the final checkpoint's clearing price is not equal to the bid's max price
            if (upperCheckpoint.clearingPrice != bidMaxPrice) {
                revert CannotExitBid();
            }
        }

        // If there is an `upperCheckpoint` that means that the bid had a period where it was partially filled.
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

        _processExit(_bidId, tokensFilled, currencySpentQ96);
    }

    /// @inheritdoc IContinuousClearingAuction
    function claimTokens(uint256 _bidId) external onlyAfterClaimBlock ensureEndBlockIsCheckpointed {
        // Tokens cannot be claimed if the auction did not graduate
        if (!_isGraduated()) revert NotGraduated();

        (address owner, uint256 tokensFilled) = _internalClaimTokens(_bidId);

        if (tokensFilled > 0) {
            Currency.wrap(address(TOKEN)).transfer(owner, tokensFilled);
            emit TokensClaimed(_bidId, owner, tokensFilled);
        }
    }

    /// @inheritdoc IContinuousClearingAuction
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
                revert BatchClaimDifferentOwner(bidOwner, _owner);
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
    /// @param _bidId The id of the bid
    /// @return owner The owner of the bid
    /// @return tokensFilled The amount of tokens filled
    function _internalClaimTokens(uint256 _bidId) internal returns (address owner, uint256 tokensFilled) {
        Bid storage $bid = _getBid(_bidId);
        if ($bid.exitedBlock == 0) revert BidNotExited();

        // Set return values
        owner = $bid.owner;
        tokensFilled = $bid.tokensFilled;

        // Set the tokens filled to 0
        $bid.tokensFilled = 0;
    }

    /// @inheritdoc IContinuousClearingAuction
    function sweepCurrency() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed {
        // Cannot sweep if already swept
        if (sweepCurrencyBlock != 0) revert CannotSweepCurrency();
        // Cannot sweep currency if the auction has not graduated, as all of the Currency must be refunded
        if (!_isGraduated()) revert NotGraduated();
        _sweepCurrency(_getBlockNumberish(), _currencyRaised());
    }

    /// @inheritdoc IContinuousClearingAuction
    function sweepUnsoldTokens() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed {
        if (sweepUnsoldTokensBlock != 0) revert CannotSweepTokens();
        uint256 unsoldTokens;
        if (_isGraduated()) {
            uint256 totalSupplyQ96 = uint256(TOTAL_SUPPLY) << FixedPoint96.RESOLUTION;
            unsoldTokens = totalSupplyQ96.scaleUpToX7().saturatingSub($totalClearedQ96_X7).divUint256(FixedPoint96.Q96)
                .scaleDownToUint256();
        } else {
            unsoldTokens = TOTAL_SUPPLY;
        }
        _sweepUnsoldTokens(_getBlockNumberish(), unsoldTokens);
    }

    // Getters
    /// @inheritdoc IContinuousClearingAuction
    function currency() external view returns (address) {
        return Currency.unwrap(CURRENCY);
    }

    /// @inheritdoc IContinuousClearingAuction
    function token() external view returns (address) {
        return address(TOKEN);
    }

    /// @inheritdoc IContinuousClearingAuction
    function totalSupply() external view returns (uint128) {
        return TOTAL_SUPPLY;
    }

    /// @inheritdoc IContinuousClearingAuction
    function tokensRecipient() external view returns (address) {
        return TOKENS_RECIPIENT;
    }

    /// @inheritdoc IContinuousClearingAuction
    function fundsRecipient() external view returns (address) {
        return FUNDS_RECIPIENT;
    }

    /// @inheritdoc IContinuousClearingAuction
    function startBlock() external view returns (uint64) {
        return START_BLOCK;
    }

    /// @inheritdoc IContinuousClearingAuction
    function endBlock() external view returns (uint64) {
        return END_BLOCK;
    }

    /// @inheritdoc IContinuousClearingAuction
    function claimBlock() external view returns (uint64) {
        return CLAIM_BLOCK;
    }

    /// @inheritdoc IContinuousClearingAuction
    function validationHook() external view returns (IValidationHook) {
        return VALIDATION_HOOK;
    }

    /// @inheritdoc IContinuousClearingAuction
    function currencyRaisedQ96_X7() external view returns (ValueX7) {
        return $currencyRaisedQ96_X7;
    }

    /// @inheritdoc IContinuousClearingAuction
    function sumCurrencyDemandAboveClearingQ96() external view returns (uint256) {
        return $sumCurrencyDemandAboveClearingQ96;
    }

    /// @inheritdoc IContinuousClearingAuction
    function totalClearedQ96_X7() external view returns (ValueX7) {
        return $totalClearedQ96_X7;
    }

    /// @inheritdoc IContinuousClearingAuction
    function totalCleared() public view returns (uint256) {
        return $totalClearedQ96_X7.divUint256(FixedPoint96.Q96).scaleDownToUint256();
    }
}
