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
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {MPSLib} from './libraries/MPSLib.sol';
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './libraries/ValueX7X7Lib.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
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
    using DemandLib for Demand;
    using SafeCastLib for uint256;
    using ValidationHookLib for IValidationHook;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    /// @notice Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook internal immutable VALIDATION_HOOK;

    /// @notice The sum of demand in ticks above the clearing price
    Demand public sumDemandAboveClearing;
    /// @notice Whether the TOTAL_SUPPLY of tokens has been received
    bool private _tokensReceived;
    /// @notice Whether the rollover supply multiplier has been set
    ///         which only happens after the auction becomes fully subscribed, at which point the supply schedule becomes deterministic
    ///         When this is true the supply sold in a block is equal to _rolloverSupplyMultiplier * that block (or range's) `mps`
    bool internal _rolloverSupplyMultiplierSet;
    /// @notice A packed uint256 containing the `remainingSupplyX7X7` and `remainingMps` values derived from the checkpoint
    ///         immediately before the auction becomes fully subscribed. The ratio of these helps account for rollover supply.
    uint256 internal _packedRolloverSupplyMultiplier;

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        TokenCurrencyStorage(
            _token,
            _parameters.currency,
            _totalSupply,
            _parameters.tokensRecipient,
            _parameters.fundsRecipient,
            _parameters.graduationThresholdMps
        )
        TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        TOKENS_RECIPIENT = _parameters.tokensRecipient;
        FUNDS_RECIPIENT = _parameters.fundsRecipient;
        CLAIM_BLOCK = _parameters.claimBlock;
        VALIDATION_HOOK = IValidationHook(_parameters.validationHook);

        if (FLOOR_PRICE == 0) revert FloorPriceIsZero();
        if (TICK_SPACING == 0) revert TickSpacingIsZero();
        if (CLAIM_BLOCK < END_BLOCK) revert ClaimBlockIsBeforeEndBlock();
        if (FUNDS_RECIPIENT == address(0)) revert FundsRecipientIsZero();
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (block.number < END_BLOCK) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for functions which can only be called after the auction is started and the tokens have been received
    modifier onlyActiveAuction() {
        if (block.number < START_BLOCK) revert AuctionNotStarted();
        if (!_tokensReceived) revert TokensNotReceived();
        _;
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external {
        // Use the normal totalSupply value instead of the scaled up X7 value
        if (TOKEN.balanceOf(address(this)) < TOTAL_SUPPLY) {
            revert IDistributionContract__InvalidAmountReceived();
        }
        _tokensReceived = true;
        emit TokensReceived(TOTAL_SUPPLY);
    }

    /// @notice External function to check if the auction has graduated as of the latest checkpoint
    /// @dev The latest checkpoint may be out of date
    /// @return bool Whether the auction has graduated or not
    function isGraduated() external view returns (bool) {
        return _isGraduated(latestCheckpoint());
    }

    /// @notice Whether the auction has graduated as of the given checkpoint (sold more than the graduation threshold)
    function _isGraduated(Checkpoint memory _checkpoint) internal view returns (bool) {
        return _checkpoint.totalClearedX7X7.gte(
            TOTAL_SUPPLY_X7_X7.mulUint256(GRADUATION_THRESHOLD_MPS).divUint256(MPSLib.MPS)
        );
    }

    /// @notice Get the rollover supply multiplier from unpacking the totalCleared and cumulative mps from the packed value
    /// @dev Must only be called after the values have been set
    /// @return The total cleared and (MPSLib.MPS - saved cumulativeMps)
    function _getRolloverSupplyMultiplier() internal view returns (ValueX7X7, uint24) {
        uint256 packed = _packedRolloverSupplyMultiplier;
        return (ValueX7X7.wrap(packed & MASK_LOWER_232_BITS), uint24(packed >> 232));
    }

    /// @notice Set the rollover supply multiplier by packing the total cleared and cumulative mps into one word
    /// @dev This is guaranteed to fit because the TOTAL_SUPPLY_X7_X7 is checked to be less than type(uint232).max..
    ///      And because remainingSupplyX7X7 must be <= TOTAL_SUPPLY_X7_X7.
    /// @param remainingSupplyX7X7 The remaining supply to be sold at the checkpoint
    /// @param remainingMps The remaining mps in the auction at the checkpoint
    function _setRolloverSupplyMultiplier(ValueX7X7 remainingSupplyX7X7, uint24 remainingMps) internal {
        uint256 packed = uint256(remainingMps) << 232 | ValueX7X7.unwrap(remainingSupplyX7X7);
        _packedRolloverSupplyMultiplier = packed;
        _rolloverSupplyMultiplierSet = true;
    }

    /// @notice Return a new checkpoint after advancing the current checkpoint by some `mps`
    ///         This function updates the cumulative values of the checkpoint, requiring that
    ///         `clearingPrice` is up to to date
    /// @param _checkpoint The checkpoint to transform
    /// @param deltaMps The number of mps to add
    /// @return The transformed checkpoint
    function _transformCheckpoint(Checkpoint memory _checkpoint, uint24 deltaMps)
        internal
        returns (Checkpoint memory)
    {
        // This value should have been divided by MPS, we implicitly remove it to wrap it as a ValueX7X7
        ValueX7X7 resolvedDemandAboveClearingPriceX7X7 =
            _checkpoint.sumDemandAboveClearingPrice.resolveRoundingUp(_checkpoint.clearingPrice).upcast();
        // Calculate the supply to be cleared based on demand above the clearing price
        ValueX7X7 supplyClearedX7X7;
        // If the clearing price is above the floor price the auction is fully subscribed and we can sell the available supply
        if (_checkpoint.clearingPrice > FLOOR_PRICE) {
            if (!_rolloverSupplyMultiplierSet) {
                // Set the cache with the values in _checkpoint, which represents the state of the auction before it becomes fully subscribed
                _setRolloverSupplyMultiplier(
                    TOTAL_SUPPLY_X7_X7.sub(_checkpoint.totalClearedX7X7), MPSLib.MPS - _checkpoint.cumulativeMps
                );
            }
            // The supply sold over `deltaMps` is deterministic since there is no more roll over supply
            // We get the cached total cleared and remaining mps for use in the calculations below. These values
            // make up the multiplier which helps account for rollover supply.
            (ValueX7X7 cachedRemainingSupplyX7X7, uint24 cachedRemainingMps) = _getRolloverSupplyMultiplier();
            /**
             * The supply sold to the clearing price is the supply sold minus the tokens sold to bidders above the clearing price
             * Supply is calculated as:
             *       (totalSupply - totalCleared) * mps                            (TOTAL_SUPPLY_X7_X7 - totalClearedX7X7)
             *      ------------------------------------ , also can be written as  --------------------------------------- * deltaMps
             *              MPS - cumulativeMps                                                 MPS - cumulativeMps
             *
             * Substituting in the cached remaining supply and remaining mps:
             *       cachedRemainingSupplyX7X7
             *      ---------------------------- * deltaMps
             *            cachedRemainingMps
             *
             * Writing out the full equation:
             *       cachedRemainingSupplyX7X7                     resolvedDemandAboveClearingPriceX7 * deltaMps
             *      ------------------------------- * deltaMps -      -------------------------------------
             *            cachedRemainingMps                                        MPSLib.MPS
             *
             * !! We multiply the RHS (demand) by MPSLib.MPS to remove the division and turn the result into an X7X7 value !!
             *
             * Finding common denominator of cachedRemainingMps
             *       cachedRemainingSupplyX7X7 * deltaMps - resolvedDemandAboveClearingPriceX7 * deltaMps * cachedRemainingMps
             *      -----------------------------------------------------------------------------------------------------------------------
             *            cachedRemainingMps
             *
             * Moving out `deltaMps` and multiply by MPSLib.MPS to turn it into a ValueX7X7
             *       deltaMps * (cachedRemainingSupplyX7X7 - resolvedDemandAboveClearingPriceX7 * cachedRemainingMps)
             *      -----------------------------------------------------------------------------------------------------------------------
             *            cachedRemainingMps
             *
             * Arriving at the final fullMulDiv below.
             */
            ValueX7X7 supplySoldToClearingPriceX7X7 = (
                cachedRemainingSupplyX7X7.sub(resolvedDemandAboveClearingPriceX7X7.mulUint256(cachedRemainingMps))
            ).wrapAndFullMulDiv(deltaMps, cachedRemainingMps);
            // After finding the supply sold to the clearing price, we add the demand above the clearing price to get the total supply sold
            supplyClearedX7X7 =
                supplySoldToClearingPriceX7X7.add(resolvedDemandAboveClearingPriceX7X7.mulUint256(deltaMps));
            // Finally, update the cumulative supply sold to the clearing price value
            _checkpoint.cumulativeSupplySoldToClearingPriceX7X7 =
                _checkpoint.cumulativeSupplySoldToClearingPriceX7X7.add(supplySoldToClearingPriceX7X7);
        }
        // Otherwise, we can only sell tokens equal to the current demand above the clearing price
        else {
            // Clear supply equal to the resolved demand above the clearing price over the given `deltaMps`
            supplyClearedX7X7 = resolvedDemandAboveClearingPriceX7X7.mulUint256(deltaMps);
            // supplySoldToClearing price is zero here because the auction is not fully subscribed yet
        }
        _checkpoint.totalClearedX7X7 = _checkpoint.totalClearedX7X7.add(supplyClearedX7X7);
        _checkpoint.cumulativeMps += deltaMps;
        _checkpoint.cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(deltaMps, _checkpoint.clearingPrice);
        return _checkpoint;
    }

    /// @notice Advance the current step until the current block is within the step
    /// @dev The checkpoint must be up to date since `transform` depends on the clearingPrice
    function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint64 blockNumber)
        internal
        returns (Checkpoint memory)
    {
        // Advance the current step until the current block is within the step
        // Start at the larger of the last checkpointed block or the start block of the current step
        uint64 start = step.startBlock < lastCheckpointedBlock ? lastCheckpointedBlock : step.startBlock;
        uint64 end = step.endBlock;

        uint24 mps = step.mps;
        while (blockNumber > end) {
            _checkpoint = _transformCheckpoint(_checkpoint, uint24((end - start) * mps));
            start = end;
            if (end == END_BLOCK) break;
            AuctionStep memory _step = _advanceStep();
            mps = _step.mps;
            end = _step.endBlock;
        }
        return _checkpoint;
    }

    /// @notice Calculate the new clearing price, given the minimum clearing price and the remaining supply in the auction
    /// @param minimumClearingPrice The minimum clearing price, which will either be the floor price or the last iterated `nextActiveTickPrice`
    /// @param remainingMpsInAuction The remaining mps in the auction which is MPSLib.MPS minus the cumulative mps so far
    /// @param remainingSupplyX7X7 The result of TOTAL_SUPPLY_X7_X7 minus the total cleared supply so far
    function _calculateNewClearingPrice(
        uint256 minimumClearingPrice,
        uint24 remainingMpsInAuction,
        ValueX7X7 remainingSupplyX7X7
    ) internal view returns (uint256) {
        /**
         * Calculate the clearing price by dividing the currencyDemandX7 by the quotient minus the tokenDemandX7, following `currency / tokens = price`
         * We find the ratio of all exact input demand to the amount of tokens available (from remaining supply minus tokenDemandX7)
         *
         * At this point, we know that the new clearing price must be between `minimumClearingPrice` and `nextActiveTickPrice`, inclusive of both bounds.
         * We can use the following equation to find the price:
         *   currencyDemandX7 * Q96 * mps         [  (totalSupplyX7 - totalClearedX7) * mps            tokenDemandX7 * mps      ]
         *   ---------------------------------  / [  ---------------------------------      -   ------------------------------  ]
         *             MPSLib.MPS                 [     MPSLib.MPS - cumulativeMps                     MPSLib.MPS               ]
         *
         * Finding common denominator for the RHS:
         *                                        [ (totalSupplyX7 - totalClearedX7) * mps * MPSLib.MPS - tokenDemandX7 * mps * (MPSLib.MPS - cumulativeMps) ]
         *                                      / [ ----------------------------------------------------------------------------------------------------     ]
         *                                        [                             (MPSLib.MPS - cumulativeMps) * MPSLib.MPS                                    ]
         * Rewriting as multiplication by reciprocal:
         *   currencyDemandX7 * Q96 * mps         [                             (MPSLib.MPS - cumulativeMps) * MPSLib.MPS                                    ]
         *   ---------------------------------  * [ ----------------------------------------------------------------------------------------------------     ]
         *             MPSLib.MPS                 [ (totalSupplyX7 - totalClearedX7) * mps * MPSLib.MPS - tokenDemandX7 * mps * (MPSLib.MPS - cumulativeMps) ]
         *
         * Cancelling out the `mps` terms and lone `MPSLib.MPS` terms:
         *                                        [                             (MPSLib.MPS - cumulativeMps)                                                 ]
         *   currencyDemandX7 * Q96             * [ ----------------------------------------------------------------------------------------------------     ]
         *                                        [ (totalSupplyX7 - totalClearedX7) * MPSLib.MPS - tokenDemandX7 * (MPSLib.MPS - cumulativeMps)             ]
         *
         * Observe that (totalSupplyX7 - totalClearedX7) * MPSLib.MPS is equal to `remainingSupplyX7X7`, since it is scaled up by MPSLib.MPS a second time
         * Now we can substitute in `remainingSupplyX7X7` and `remainingMpsInAuction` into the equation
         * We use fullMulDivUp to allow for intermediate overflows and ensure that the final clearing price is rounded up because we bias towards
         * higher prices which results in less tokens being sold (since price is currency / token).
         */
        uint256 _clearingPrice = ValueX7.unwrap(
            sumDemandAboveClearing.currencyDemandX7.fullMulDivUp(
                ValueX7.wrap(FixedPoint96.Q96 * uint256(remainingMpsInAuction)),
                remainingSupplyX7X7.downcast().sub(
                    sumDemandAboveClearing.tokenDemandX7.mulUint256(remainingMpsInAuction)
                )
            )
        );

        // If the new clearing price is below the minimum clearing price return the minimum clearing price
        if (_clearingPrice < minimumClearingPrice) return minimumClearingPrice;
        // Otherwise, round up to the nearest tick boundary
        // This will result in a higher price which means less tokens will be sold than expected
        uint256 remainder = _clearingPrice % TICK_SPACING;
        if (remainder != 0) {
            return ((_clearingPrice + TICK_SPACING) - remainder);
        }
        return _clearingPrice;
    }

    /// @notice Update the latest checkpoint to the current step
    /// @dev This updates the state of the auction accounting for the bids placed after the last checkpoint
    ///      Checkpoints are created at the top of each block with a new bid and does NOT include that bid
    ///      Because of this, we need to calculate what the new state of the Auction should be before updating
    ///      purely on the supply we will sell to the potentially updated `sumDemandAboveClearing` value
    ///
    ///      After the checkpoint is made up to date we can use those values to update the cumulative values
    ///      depending on how much time has passed since the last checkpoint
    function _updateLatestCheckpointToCurrentStep(uint64 blockNumber) internal returns (Checkpoint memory) {
        Checkpoint memory _checkpoint = latestCheckpoint();
        // If step.mps is 0, advance to the current step before calculating the supply
        if (step.mps == 0) _advanceToCurrentStep(_checkpoint, blockNumber);

        // The clearing price can never be lower than the last checkpoint. If the clearingPrice is zero, set it to the floor price
        uint256 _clearingPrice = _checkpoint.clearingPrice.coalesce(FLOOR_PRICE);
        if (step.mps > 0) {
            // All active demand above the current clearing price
            Demand memory _sumDemandAboveClearing = sumDemandAboveClearing;
            // The next price tick initialized with demand is the `nextActiveTickPrice`
            Tick memory _nextActiveTick = getTick(nextActiveTickPrice);

            /**
             * For clearing price related calculations, we need to determine the amount of supply sold over `mps` as well as the corresponding demand.
             * - Supply is found by multiplying the actual supply sold so far by the current supply issuance rate (step.mps),
             *   and dividing by the remaining mps in the auction to account for any previously unsold supply which is rolled over.
             *
             *   For example: (totalSupply - _checkpoint.totalCleared) * step.mps / (MPSLib.MPS - _checkpoint.cumulativeMps)
             *
             * - However, multpling by `step.mps` and dividing by `(MPSLib.MPS - _checkpoint.cumulativeMps)` loses precision, and we want to avoid it whenever possible.
             *   We save `(MPSLib.MPS - _checkpoint.cumulativeMps)` here to multiply by later when we want to cancel out the division.
             */
            uint24 remainingMpsInAuction = MPSLib.MPS - _checkpoint.cumulativeMps;

            /**
             * For a non-zero supply, iterate to find the tick where the demand at and above it is strictly less than the supply
             * If the loop reaches the highest tick in the book, `nextActiveTickPrice` will be set to MAX_TICK_PRICE
             *
             * To compare the resolved demand to the supply being sold, we have the orignal equation:
             *   R = resolvedDemand * mps / MPSLib.MPS
             *   supply = (totalSupply - _checkpoint.totalCleared) * step.mps / (MPSLib.MPS - _checkpoint.cumulativeMps)
             * We are looking for R >= supply
             *
             * Observe that because of the inequality, we can multiply both sides by `(MPSLib.MPS - _checkpoint.cumulativeMps)` to get:
             *   R * (MPSLib.MPS - _checkpoint.cumulativeMps) >= supply * mps
             *
             * Substituting R back into the equation to get:
             *   (resolvedDemand * mps / MPSLib.MPS) * (MPSLib.MPS - _checkpoint.cumulativeMps) >= supply * mps
             * Or,
             *   (resolvedDemand * mps) * (MPSLib.MPS - _checkpoint.cumulativeMps)
             *   ----------------------------------------------------------------- >= supply * mps
             *                            MPSLib.MPS
             * We can eliminate the `mps` term on both sides to get:
             *   resolvedDemand * (MPSLib.MPS - _checkpoint.cumulativeMps)
             *   ----------------------------------------------------------------- >= supply
             *                            MPSLib.MPS
             * And multiply both sides by `MPSLib.MPS` to remove the division entirely:
             *   resolvedDemand * (MPSLib.MPS - _checkpoint.cumulativeMps) >= supply * MPSLib.MPS
             *
             * Conveniently, we are already tracking supply in terms of X7X7, which is already scaled up by MPSLib.MPS,
             * so we can substitute in TOTAL_SUPPLY_X7_X7.sub(_checkpoint.totalClearedX7X7) for `supply`:
             *   resolvedDemand * (MPSLib.MPS - _checkpoint.cumulativeMps) >= TOTAL_SUPPLY_X7_X7.sub(_checkpoint.totalClearedX7X7)
             */
            while (
                _sumDemandAboveClearing.resolveRoundingUp(nextActiveTickPrice).mulUint256(remainingMpsInAuction).upcast(
                ).gte(TOTAL_SUPPLY_X7_X7.sub(_checkpoint.totalClearedX7X7))
            ) {
                // Subtract the demand at the current nextActiveTick from the total demand
                _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_nextActiveTick.demand);
                // The `nextActiveTickPrice` is now the minimum clearing price because there was enough demand to fill the supply
                _clearingPrice = nextActiveTickPrice;
                // Advance to the next tick
                uint256 _nextTickPrice = _nextActiveTick.next;
                nextActiveTickPrice = _nextTickPrice;
                _nextActiveTick = getTick(_nextTickPrice);
            }

            // Save cached state variable
            sumDemandAboveClearing = _sumDemandAboveClearing;
            // Calculate the new clearing price
            _clearingPrice = _calculateNewClearingPrice(
                _clearingPrice, remainingMpsInAuction, TOTAL_SUPPLY_X7_X7.sub(_checkpoint.totalClearedX7X7)
            );
            // Reset the cumulative supply sold to clearing price if the clearing price is different now
            if (_clearingPrice != _checkpoint.clearingPrice) {
                _checkpoint.cumulativeSupplySoldToClearingPriceX7X7 = ValueX7X7.wrap(0);
            }
            _checkpoint.sumDemandAboveClearingPrice = _sumDemandAboveClearing;
        }
        // Set the new clearing price
        _checkpoint.clearingPrice = _clearingPrice;

        /// We can now advance the `step` to the current step for the block
        /// This modifies the `_checkpoint` to ensure the cumulative variables are correctly accounted for
        /// Checkpoint.transform is dependent on:
        /// - clearing price
        /// - sumDemandAboveClearingPrice
        return _advanceToCurrentStep(_checkpoint, blockNumber);
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @param blockNumber The block number to checkpoint at
    function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        if (blockNumber == lastCheckpointedBlock) return latestCheckpoint();

        // Update the latest checkpoint, accounting for new bids and advances in supply schedule
        _checkpoint = _updateLatestCheckpointToCurrentStep(blockNumber);
        _checkpoint.mps = step.mps;

        // Now account for any time in between this checkpoint and the greater of the start of the step or the last checkpointed block
        uint64 blockDelta =
            blockNumber - (step.startBlock > lastCheckpointedBlock ? step.startBlock : lastCheckpointedBlock);
        uint24 mpsSinceLastCheckpoint = uint256(_checkpoint.mps * blockDelta).toUint24();

        _checkpoint = _transformCheckpoint(_checkpoint, mpsSinceLastCheckpoint);
        _insertCheckpoint(_checkpoint, blockNumber);

        emit CheckpointUpdated(
            blockNumber, _checkpoint.clearingPrice, _checkpoint.totalClearedX7X7, _checkpoint.cumulativeMps
        );
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory _checkpoint) {
        return _unsafeCheckpoint(END_BLOCK);
    }

    function _submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        Checkpoint memory _checkpoint = checkpoint();

        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        VALIDATION_HOOK.handleValidate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        if (maxPrice <= _checkpoint.clearingPrice) revert InvalidBidPrice();

        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        Bid memory bid;
        (bid, bidId) = _createBid(exactIn, amount, owner, maxPrice, _checkpoint.cumulativeMps);
        Demand memory bidDemand = bid.toDemand();

        _updateTickDemand(maxPrice, bidDemand);

        sumDemandAboveClearing = sumDemandAboveClearing.add(bidDemand);

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
            CURRENCY.transfer(_owner, refund);
        }

        emit BidExited(bidId, _owner, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function checkpoint() public onlyActiveAuction returns (Checkpoint memory _checkpoint) {
        if (block.number > END_BLOCK) {
            return _getFinalCheckpoint();
        }
        return _unsafeCheckpoint(uint64(block.number));
    }

    /// @inheritdoc IAuction
    /// @dev Bids can be submitted anytime between the startBlock and the endBlock.
    function submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable onlyActiveAuction returns (uint256) {
        // Bids cannot be submitted at the endBlock or after
        if (block.number >= END_BLOCK) revert AuctionIsOver();
        uint256 requiredCurrencyAmount = BidLib.inputAmount(exactIn, amount, maxPrice);
        if (requiredCurrencyAmount == 0) revert InvalidAmount();
        if (CURRENCY.isAddressZero()) {
            if (msg.value != requiredCurrencyAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(
                Currency.unwrap(CURRENCY), msg.sender, address(this), requiredCurrencyAmount
            );
        }
        return _submitBid(maxPrice, exactIn, amount, owner, prevTickPrice, hookData);
    }

    /// @inheritdoc IAuction
    function exitBid(uint256 bidId) external onlyAfterAuctionIsOver {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        if (!_isGraduated(finalCheckpoint)) {
            // In the case that the auction did not graduate, fully refund the bid
            return _processExit(bidId, bid, 0, bid.inputAmount());
        }

        if (bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();
        /// @dev Bid was fully filled and the auction is now over
        (uint256 tokensFilled, uint256 currencySpent) =
            _accountFullyFilledCheckpoints(finalCheckpoint, _getCheckpoint(bid.startBlock), bid);

        _processExit(bidId, bid, tokensFilled, bid.inputAmount() - currencySpent);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lower, uint64 outbidBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        Checkpoint memory finalCheckpoint = _unsafeCheckpoint(END_BLOCK);
        Checkpoint memory lastFullyFilledCheckpoint = _getCheckpoint(lower);

        // Since `lower` points to the last fully filled Checkpoint, its next Checkpoint must be >= bid.maxPrice
        // It must also cannot be before the bid's startCheckpoint
        if (_getCheckpoint(lastFullyFilledCheckpoint.next).clearingPrice < bid.maxPrice || lower < bid.startBlock) {
            revert InvalidCheckpointHint();
        }

        uint256 tokensFilled;
        uint256 currencySpent;
        // If the lastFullyFilledCheckpoint is not 0, account for the fully filled checkpoints
        if (lastFullyFilledCheckpoint.clearingPrice > 0) {
            (tokensFilled, currencySpent) =
                _accountFullyFilledCheckpoints(lastFullyFilledCheckpoint, startCheckpoint, bid);
        }

        /// Upper checkpoint is the last checkpoint where the bid is partially filled
        Checkpoint memory upperCheckpoint;
        /// @dev Bid has been outbid
        if (bid.maxPrice < finalCheckpoint.clearingPrice) {
            Checkpoint memory outbidCheckpoint = _getCheckpoint(outbidBlock);
            upperCheckpoint = _getCheckpoint(outbidCheckpoint.prev);
            // It's possible that there is no checkpoint with price equal to the bid's maxPrice
            // In this case the bid is never partially filled and we can skip that accounting logic
            // So upperCheckpoint.clearingPrice can be < or == the bid's maxPrice here
            if (outbidCheckpoint.clearingPrice <= bid.maxPrice || upperCheckpoint.clearingPrice > bid.maxPrice) {
                revert InvalidCheckpointHint();
            }
        }
        /// @dev Auction ended and the final price is the bid's max price
        ///      `outbidBlock` is not checked here and can be zero
        else if (block.number >= END_BLOCK && bid.maxPrice == finalCheckpoint.clearingPrice) {
            upperCheckpoint = finalCheckpoint;
        } else {
            revert CannotExitBid();
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
        if (upperCheckpoint.clearingPrice == bid.maxPrice) {
            (uint256 partialTokensFilled, uint256 partialCurrencySpent) = _accountPartiallyFilledCheckpoints(
                upperCheckpoint.cumulativeSupplySoldToClearingPriceX7X7,
                bid.toDemand().resolveRoundingUp(bid.maxPrice),
                getTick(bid.maxPrice).demand.resolveRoundingUp(bid.maxPrice),
                bid.maxPrice
            );
            tokensFilled += partialTokensFilled;
            currencySpent += partialCurrencySpent;
        }

        _processExit(bidId, bid, tokensFilled, bid.inputAmount() - currencySpent);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock == 0) revert BidNotExited();
        if (block.number < CLAIM_BLOCK) revert NotClaimable();
        if (!_isGraduated(_getFinalCheckpoint())) revert NotGraduated();

        uint256 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        Currency.wrap(address(TOKEN)).transfer(bid.owner, tokensFilled);

        emit TokensClaimed(bidId, bid.owner, tokensFilled);
    }

    /// @inheritdoc IAuction
    function sweepCurrency() external onlyAfterAuctionIsOver {
        // Cannot sweep if already swept
        if (sweepCurrencyBlock != 0) revert CannotSweepCurrency();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        // Cannot sweep currency if the auction has not graduated, as the Currency must be refunded
        if (!_isGraduated(finalCheckpoint)) revert NotGraduated();
        _sweepCurrency(finalCheckpoint.getCurrencyRaised());
    }

    /// @inheritdoc IAuction
    function sweepUnsoldTokens() external onlyAfterAuctionIsOver {
        if (sweepUnsoldTokensBlock != 0) revert CannotSweepTokens();
        Checkpoint memory finalCheckpoint = _getFinalCheckpoint();
        if (_isGraduated(finalCheckpoint)) {
            _sweepUnsoldTokens(
                // Subtract the total cleared from the total supply before scaling down to X7
                (TOTAL_SUPPLY_X7_X7.sub(_getFinalCheckpoint().totalClearedX7X7).scaleDownToValueX7())
                    // Then finally scale down to uint256
                    .scaleDownToUint256()
            );
        } else {
            // For simplicity we use the uint256 totalSupply value here instead of the scaled up X7 value
            _sweepUnsoldTokens(TOTAL_SUPPLY);
        }
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
}
