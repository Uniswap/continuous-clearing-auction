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
import {MPSLib, ValueX7} from './libraries/MPSLib.sol';
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

import {console2} from 'forge-std/console2.sol';

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
    using MPSLib for *;

    /// @notice Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook internal immutable VALIDATION_HOOK;

    /// @notice The sum of demand in ticks above the clearing price
    Demand public sumDemandAboveClearing;

    Checkpoint public lastCheckpointBeforeFullySubscribed;

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

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external view {
        // Use the normal totalSupply value instead of the scaled up X7 value
        if (TOKEN.balanceOf(address(this)) < TOTAL_SUPPLY) {
            revert IDistributionContract__InvalidAmountReceived();
        }
    }

    /// @notice Whether the auction has graduated as of the latest checkpoint (sold more than the graduation threshold)
    function isGraduated() public view returns (bool) {
        return latestCheckpoint().totalCleared.gte(ValueX7.unwrap(TOTAL_SUPPLY_X7.scaleByMps(GRADUATION_THRESHOLD_MPS)));
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
        // Resolved demand above the clearing price over `deltaMps`
        // This loses precision up to `deltaMps` significant figures
        ValueX7 demandAboveClearingPriceMpsX7 =
            _checkpoint.sumDemandAboveClearingPrice.scaleByMps(deltaMps).resolve(_checkpoint.clearingPrice);
        // Calculate the supply to be cleared based on demand above the clearing price
        ValueX7 supplyClearedX7;
        ValueX7 supplySoldToClearingPriceX7;
        // If the clearing price is above the floor price we can sell the available supply
        // Otherwise, we can only sell the demand above the clearing price
        if (_checkpoint.clearingPrice > FLOOR_PRICE) {
            // If unset, set the lastCheckpointBeforeFullySubscribed to the current _checkpoint
            // The `totalCleared` and `cumulativeMps` values have not been updated yet
            if (lastCheckpointBeforeFullySubscribed.totalCleared.eq(0)) {
                lastCheckpointBeforeFullySubscribed = _checkpoint;
            }
            supplyClearedX7 = TOTAL_SUPPLY_X7.sub(lastCheckpointBeforeFullySubscribed.totalCleared).mulUint256(deltaMps)
                .divUint256(MPSLib.MPS - lastCheckpointBeforeFullySubscribed.cumulativeMps);

            console2.log('supplyClearedX7', ValueX7.unwrap(supplyClearedX7));
            console2.log('demandAboveClearingPriceMpsX7', ValueX7.unwrap(demandAboveClearingPriceMpsX7));

            supplySoldToClearingPriceX7 = supplyClearedX7.sub(demandAboveClearingPriceMpsX7);
            _checkpoint.cumulativeSupplySoldToClearingPriceX7 =
                _checkpoint.cumulativeSupplySoldToClearingPriceX7.add(supplySoldToClearingPriceX7);
        } else {
            supplyClearedX7 = demandAboveClearingPriceMpsX7;
            // supplySoldToClearing price is zero here
        }
        _checkpoint.totalCleared = _checkpoint.totalCleared.add(supplyClearedX7);
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

    /// @notice Calculate the new clearing price, given the minimum clearing price and the quotient
    /// @param minimumClearingPrice The minimum clearing price which MUST be >= the floor price
    /// @param quotientX7 The quotient used in the clearing price calculation
    function _calculateNewClearingPrice(uint256 minimumClearingPrice, ValueX7 quotientX7)
        internal
        view
        returns (uint256)
    {
        /**
         * Calculate the clearing price by dividing the currencyDemandX7 by the quotient minus the tokenDemandX7, following `currency / tokens = price`
         * We find the ratio of all exact input demand to the amount of tokens available (from supply minus tokenDemandX7)
         * However, scaling the demand by mps loses precision when dividing by MPSLib.MPS. To avoid this, we use the precalculated quotientX7.
         *
         * Formula derivation:
         *
         *   ((currencyDemandX7 * step.mps) / MPSLib.MPS) * Q96
         *   ────────────────────────────────────────────────────────────────────────────────────────────────────────
         *   (remainingSupply * step.mps / (MPSLib.MPS - cumulativeMps)) - ((tokenDemandX7 * step.mps) / MPSLib.MPS)
         *
         * Observe that we can cancel out the `step.mps` component in the numerator and denominator:
         *
         *   (currencyDemandX7 / MPSLib.MPS) * Q96
         *   ──────────────────────────────────────────────────────────────────────────────────────
         *   (remainingSupply / (MPSLib.MPS - cumulativeMps)) - (tokenDemandX7 / MPSLib.MPS)
         *
         * Multiply both sides by MPSLib.MPS:
         *
         *   currencyDemandX7 * Q96
         *   ─────────────────────────────────────────────────────────────────────────────────────
         *   (remainingSupply * MPSLib.MPS / (MPSLib.MPS - cumulativeMps)) - tokenDemandX7
         *
         * Substituting quotientX7 for (remainingSupply * MPSLib.MPS / (MPSLib.MPS - cumulativeMps)):
         *
         *   currencyDemandX7 * Q96
         *   ──────────────────────
         *   quotientX7 - tokenDemandX7
         */
        uint256 _clearingPrice = ValueX7.unwrap(
            sumDemandAboveClearing.currencyDemandX7.fullMulDiv(
                ValueX7.wrap(FixedPoint96.Q96), quotientX7.sub(sumDemandAboveClearing.tokenDemandX7)
            )
        );

        // If the new clearing price is below the minimum clearing price return the minimum clearing price
        if (_clearingPrice < minimumClearingPrice) return minimumClearingPrice;
        // Otherwise, round down to the nearest tick boundary
        return (_clearingPrice - (_clearingPrice % TICK_SPACING));
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
             * Calculate the quotient used in the tick iteration and clearing price calculation
             * - We can calculate the supply sold in this block by finding the actual supply sold so far,
             *   multiplying it by the current supply issuance rate (step.mps), and dividing by the remaining mps in the auction.
             *   This accounts for any previously unsold supply which is rolled over.
             * - However, multpling by `step.mps` and dividing by `MPSLib.MPS` loses precision, so we want to avoid it whenever possible.
             *   Thus, we calculate an intermediate value here that simplifies future calculations.
             */
            ValueX7 quotientX7 = TOTAL_SUPPLY_X7.sub(_checkpoint.totalCleared).mulUint256(MPSLib.MPS).divUint256(
                MPSLib.MPS - _checkpoint.cumulativeMps
            );

            /**
             * For a non-zero supply, iterate to find the tick where the demand at and above it is strictly less than the supply
             * Sets nextActiveTickPrice to MAX_TICK_PRICE if the highest tick in the book is reached
             *
             * We must compare the resolved demand following the current issuance schedule (step.mps) to the supply being sold
             * But we don't want to multiply by `step.mps` and divide by `MPSLib.MPS` because it loses precision
             * Thus, we multiply both sides by `MPSLib.MPS` instead of dividing such that it is equivalent.
             */
            while (_sumDemandAboveClearing.resolve(nextActiveTickPrice).gte(ValueX7.unwrap(quotientX7))) {
                // Subtract the demand at `nextActiveTickPrice`
                _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_nextActiveTick.demand);
                // The `nextActiveTickPrice` is now the minimum clearing price because there was enough demand to fill the supply
                _clearingPrice = nextActiveTickPrice;
                // Advance to the next tick
                uint256 _nextTickPrice = _nextActiveTick.next;
                nextActiveTickPrice = _nextTickPrice;
                _nextActiveTick = getTick(_nextTickPrice);
            }

            // Save state variables
            sumDemandAboveClearing = _sumDemandAboveClearing;
            // Calculate the new clearing price
            _clearingPrice = _calculateNewClearingPrice(_clearingPrice, quotientX7);
            // Reset the cumulative supply sold to clearing price if the clearing price is different now
            if (_clearingPrice != _checkpoint.clearingPrice) {
                _checkpoint.cumulativeSupplySoldToClearingPriceX7 = ValueX7.wrap(0);
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
        if (blockNumber < START_BLOCK) revert AuctionNotStarted();

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
            blockNumber, _checkpoint.clearingPrice, _checkpoint.totalCleared, _checkpoint.cumulativeMps
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
    function checkpoint() public returns (Checkpoint memory _checkpoint) {
        if (block.number > END_BLOCK) revert AuctionIsOver();
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
    ) external payable returns (uint256) {
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
        if (!isGraduated()) {
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
                upperCheckpoint.cumulativeSupplySoldToClearingPriceX7,
                bid.toDemand().resolve(bid.maxPrice),
                getTick(bid.maxPrice).demand.resolve(bid.maxPrice),
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
        if (!isGraduated()) revert NotGraduated();

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
        // Cannot sweep currency if the auction has not graduated, as the Currency must be refunded
        if (!isGraduated()) revert NotGraduated();
        _sweepCurrency(_getFinalCheckpoint().getCurrencyRaised());
    }

    /// @inheritdoc IAuction
    function sweepUnsoldTokens() external onlyAfterAuctionIsOver {
        if (sweepUnsoldTokensBlock != 0) revert CannotSweepTokens();
        if (isGraduated()) {
            _sweepUnsoldTokens((TOTAL_SUPPLY_X7.sub(_getFinalCheckpoint().totalCleared)).scaleDownToUint256());
        } else {
            // Use the uint256 totalSupply value instead of the scaled up X7 value
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
