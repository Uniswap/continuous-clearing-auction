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
    using FixedPointMathLib for uint128;
    using CurrencyLibrary for Currency;
    using BidLib for *;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using DemandLib for Demand;
    using SafeCastLib for uint256;

    /// @notice Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @notice The block at which purchased tokens can be claimed
    uint64 public immutable claimBlock;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;

    /// @notice The sum of demand in ticks above the clearing price
    Demand internal $sumDemandAboveClearing;
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
            _parameters.graduationThresholdMps,
            _parameters.fundsRecipientData
        )
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
        if (claimBlock < endBlock) revert ClaimBlockIsBeforeEndBlock();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (block.number < endBlock) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for functions which can only be called after the auction is started and the tokens have been received
    modifier onlyActiveAuction() {
        if (block.number < startBlock) revert AuctionNotStarted();
        if (!$_tokensReceived) revert TokensNotReceived();
        _;
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived() external {
        // Use the normal totalSupply value instead of the scaled up X7 value
        if (token.balanceOf(address(this)) < totalSupply) {
            revert IDistributionContract__InvalidAmountReceived();
        }
        $_tokensReceived = true;
        emit TokensReceived(totalSupply);
    }

    /// @notice External function to check if the auction has graduated as of the latest checkpoint
    /// @dev The latest checkpoint may be out of date
    /// @return bool Whether the auction has graduated or not
    function isGraduated() external view returns (bool) {
        return _isGraduated(latestCheckpoint());
    }

    /// @notice Whether the auction has graduated as of the latest checkpoint (sold more than the graduation threshold)
    function _isGraduated(Checkpoint memory _checkpoint) internal view returns (bool) {
        return _checkpoint.totalCleared >= totalSupply.fullMulDiv(graduationThresholdMps, AuctionStepLib.MPS);
    }

    /// @notice Return a new checkpoint after advancing the current checkpoint by some `mps`
    ///         This function updates the cumulative values of the checkpoint, requiring that
    ///         `clearingPrice` is up to to date
    /// @param _checkpoint The checkpoint to transform
    /// @param deltaMps The number of mps to add
    /// @return The transformed checkpoint
    function _transformCheckpoint(Checkpoint memory _checkpoint, uint24 deltaMps)
        internal
        view
        returns (Checkpoint memory)
    {
        // Calculate the tokens demanded by bidders above the clearing price, and round up to sell more to them and less to the clearingPrice.
        // This is important to ensure that a bid above the clearing price purchases its full amount
        uint128 resolvedDemandAboveClearingPriceMpsRoundedUp =
            uint128(_checkpoint.resolvedDemandAboveClearingPrice.fullMulDivUp(deltaMps, AuctionStepLib.MPS));

        uint128 supplyCleared;
        uint128 supplySoldToClearingPrice;
        // If the clearing price is above the floor price we can sell the available supply
        // Otherwise, we can only sell the demand above the clearing price
        if (_checkpoint.clearingPrice > floorPrice) {
            supplyCleared = _checkpoint.getSupply(totalSupply, deltaMps);
            supplySoldToClearingPrice = supplyCleared - resolvedDemandAboveClearingPriceMpsRoundedUp;
        } else {
            supplyCleared = resolvedDemandAboveClearingPriceMpsRoundedUp;
            // supplySoldToClearing price is zero here
        }
        _checkpoint.totalCleared += supplyCleared;
        _checkpoint.cumulativeMps += deltaMps;
        _checkpoint.cumulativeSupplySoldToClearingPrice += supplySoldToClearingPrice;
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
        uint64 start = $step.startBlock < $lastCheckpointedBlock ? $lastCheckpointedBlock : $step.startBlock;
        uint64 end = $step.endBlock;

        uint24 mps = $step.mps;
        while (blockNumber > end) {
            _checkpoint = _transformCheckpoint(_checkpoint, uint24((end - start) * mps));
            start = end;
            if (end == endBlock) break;
            AuctionStep memory _step = _advanceStep();
            mps = _step.mps;
            end = _step.endBlock;
        }
        return _checkpoint;
    }

    /// @notice Calculate the new clearing price, given:
    /// @param blockSumDemandAboveClearing The demand above the clearing price in the block
    /// @param minimumClearingPrice The minimum clearing price
    /// @param supply The token supply at or above nextActiveTickPrice in the block
    function _calculateNewClearingPrice(
        Demand memory blockSumDemandAboveClearing,
        uint256 minimumClearingPrice,
        uint128 supply
    ) internal view returns (uint256) {
        // Calculate the clearing price by first subtracting the exactOut tokenDemand then dividing by the currencyDemand, following `currency / tokens = price`
        // If the supply is zero, set clearing price to 0 to prevent division by zero.
        // If the minimum clearing price is non zero, it will be returned. Otherwise, the floor price will be returned.
        uint256 _clearingPrice = supply > 0
            ? blockSumDemandAboveClearing.currencyDemand.fullMulDiv(
                FixedPoint96.Q96, (supply - blockSumDemandAboveClearing.tokenDemand)
            )
            : 0;

        // If the new clearing price is below the minimum clearing price return the minimum clearing price
        if (_clearingPrice < minimumClearingPrice) return minimumClearingPrice;
        // If the new clearing price is below the floor price return the floor price
        if (_clearingPrice < floorPrice) return floorPrice;
        // Otherwise, round down to the nearest tick boundary
        return (_clearingPrice - (_clearingPrice % tickSpacing));
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
        if ($step.mps == 0) _advanceToCurrentStep(_checkpoint, blockNumber);
        // Get the supply being sold since the last checkpoint, accounting for rollovers of past supply
        uint128 supply = _checkpoint.getSupply(totalSupply, $step.mps);

        // All active demand above the current clearing price
        Demand memory _sumDemandAboveClearing = $sumDemandAboveClearing;
        // The clearing price can never be lower than the last checkpoint
        uint256 minimumClearingPrice = _checkpoint.clearingPrice;
        // The next price tick initialized with demand is the `nextActiveTickPrice`
        Tick memory _nextActiveTick = getTick($nextActiveTickPrice);

        // For a non-zero supply, iterate to find the tick where the demand at and above it is strictly less than the supply
        // Sets nextActiveTickPrice to MAX_TICK_PRICE if the highest tick in the book is reached
        while (_sumDemandAboveClearing.resolve($nextActiveTickPrice).applyMps($step.mps) >= supply && supply > 0) {
            // Subtract the demand at `nextActiveTickPrice`
            _sumDemandAboveClearing = _sumDemandAboveClearing.sub(_nextActiveTick.demand);
            // The `nextActiveTickPrice` is now the minimum clearing price because there was enough demand to fill the supply
            minimumClearingPrice = $nextActiveTickPrice;
            // Advance to the next tick
            uint256 _nextTickPrice = _nextActiveTick.next;
            $nextActiveTickPrice = _nextTickPrice;
            _nextActiveTick = getTick(_nextTickPrice);
        }

        // Save state variables
        $sumDemandAboveClearing = _sumDemandAboveClearing;
        // Calculate the new clearing price
        uint256 newClearingPrice =
            _calculateNewClearingPrice(_sumDemandAboveClearing.applyMps($step.mps), minimumClearingPrice, supply);
        // Reset the cumulative weighted partial fill rate if the clearing price has updated
        if (newClearingPrice != _checkpoint.clearingPrice) _checkpoint.cumulativeSupplySoldToClearingPrice = 0;
        // Update the clearing price
        _checkpoint.clearingPrice = newClearingPrice;
        _checkpoint.resolvedDemandAboveClearingPrice = _sumDemandAboveClearing.resolve(_checkpoint.clearingPrice);
        /// We can now advance the `step` to the current step for the block
        /// This modifies the `_checkpoint` to ensure the cumulative variables are correctly accounted for
        /// Checkpoint.transform is dependent on:
        /// - clearing price
        /// - resolvedDemandAboveClearingPrice
        return _advanceToCurrentStep(_checkpoint, blockNumber);
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @param blockNumber The block number to checkpoint at
    function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        if (blockNumber == $lastCheckpointedBlock) return latestCheckpoint();

        // Update the latest checkpoint, accounting for new bids and advances in supply schedule
        _checkpoint = _updateLatestCheckpointToCurrentStep(blockNumber);
        _checkpoint.mps = $step.mps;

        // Now account for any time in between this checkpoint and the greater of the start of the step or the last checkpointed block
        uint64 blockDelta =
            blockNumber - ($step.startBlock > $lastCheckpointedBlock ? $step.startBlock : $lastCheckpointedBlock);
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
        return _unsafeCheckpoint(endBlock);
    }

    function _submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint128 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        Checkpoint memory _checkpoint = checkpoint();

        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        if (address(validationHook) != address(0)) {
            validationHook.validate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        }
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        if (maxPrice <= _checkpoint.clearingPrice) revert InvalidBidPrice();

        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        uint128 adjustedDemand = amount.effectiveAmount(AuctionStepLib.MPS - _checkpoint.cumulativeMps);

        _updateTick(maxPrice, exactIn, adjustedDemand);

        bidId = _createBid(exactIn, amount, owner, maxPrice);

        if (exactIn) {
            $sumDemandAboveClearing = $sumDemandAboveClearing.addCurrencyAmount(adjustedDemand);
        } else {
            $sumDemandAboveClearing = $sumDemandAboveClearing.addTokenAmount(adjustedDemand);
        }

        emit BidSubmitted(bidId, owner, maxPrice, exactIn, amount);
    }

    /// @notice Given a bid, tokens filled and refund, process the transfers and refund
    function _processExit(uint256 bidId, Bid memory bid, uint128 tokensFilled, uint128 refund) internal {
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

        emit BidExited(bidId, _owner, tokensFilled, refund);
    }

    /// @inheritdoc IAuction
    function checkpoint() public onlyActiveAuction returns (Checkpoint memory _checkpoint) {
        if (block.number > endBlock) revert AuctionIsOver();
        return _unsafeCheckpoint(uint64(block.number));
    }

    /// @inheritdoc IAuction
    /// @dev Bids can be submitted anytime between the startBlock and the endBlock.
    function submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint128 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable onlyActiveAuction returns (uint256) {
        // Bids cannot be submitted at the endBlock or after
        if (block.number >= endBlock) revert AuctionIsOver();
        uint128 requiredCurrencyAmount = BidLib.inputAmount(exactIn, amount, maxPrice);
        if (requiredCurrencyAmount == 0) revert InvalidAmount();
        if (currency.isAddressZero()) {
            if (msg.value != requiredCurrencyAmount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert CurrencyIsNotNative();
            SafeTransferLib.permit2TransferFrom(
                Currency.unwrap(currency), msg.sender, address(this), requiredCurrencyAmount
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
        (uint128 tokensFilled, uint128 currencySpent) =
            _accountFullyFilledCheckpoints(finalCheckpoint, _getCheckpoint(bid.startBlock), bid);

        _processExit(bidId, bid, tokensFilled, bid.inputAmount() - currencySpent);
    }

    /// @inheritdoc IAuction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lower, uint64 outbidBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.exitedBlock != 0) revert BidAlreadyExited();

        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        Checkpoint memory finalCheckpoint = _unsafeCheckpoint(endBlock);
        Checkpoint memory lastFullyFilledCheckpoint = _getCheckpoint(lower);

        // Since `lower` points to the last fully filled Checkpoint, it must be < bid.maxPrice
        // The next Checkpoint after `lower` must be partially or fully filled (clearingPrice >= bid.maxPrice)
        // `lower` also cannot be before the bid's startCheckpoint
        if (
            lastFullyFilledCheckpoint.clearingPrice >= bid.maxPrice
                || _getCheckpoint(lastFullyFilledCheckpoint.next).clearingPrice < bid.maxPrice || lower < bid.startBlock
        ) {
            revert InvalidCheckpointHint();
        }

        uint128 tokensFilled;
        uint128 currencySpent;
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
        else if (block.number >= endBlock && bid.maxPrice == finalCheckpoint.clearingPrice) {
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
            (uint128 partialTokensFilled, uint128 partialCurrencySpent) = _accountPartiallyFilledCheckpoints(
                upperCheckpoint.cumulativeSupplySoldToClearingPrice,
                bid.demand(AuctionStepLib.MPS - startCheckpoint.cumulativeMps),
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
        if (block.number < claimBlock) revert NotClaimable();
        if (!_isGraduated(_getFinalCheckpoint())) revert NotGraduated();

        uint128 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        Currency.wrap(address(token)).transfer(bid.owner, tokensFilled);

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
            _sweepUnsoldTokens(totalSupply - finalCheckpoint.totalCleared);
        } else {
            _sweepUnsoldTokens(totalSupply);
        }
    }

    /// @inheritdoc IAuction
    function sumDemandAboveClearing() external view override(IAuction) returns (Demand memory) {
        return $sumDemandAboveClearing;
    }
}
