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

import {FixedPoint128} from './libraries/FixedPoint128.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValidationHookLib} from './libraries/ValidationHookLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
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
    using FixedPointMathLib for *;
    using CurrencyLibrary for Currency;
    using BidLib for *;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using SafeCastLib for uint256;
    using ValidationHookLib for IValidationHook;
    using ValueX7Lib for *;

    /// @notice The maximum price which a bid can be submitted at
    /// @dev Set during construction to type(uint256).max / TOTAL_SUPPLY
    uint256 public immutable MAX_BID_PRICE;
    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook internal immutable VALIDATION_HOOK;

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
            _parameters.fundsRecipient
        )
        TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        CLAIM_BLOCK = _parameters.claimBlock;
        VALIDATION_HOOK = IValidationHook(_parameters.validationHook);

        if (CLAIM_BLOCK < END_BLOCK) revert ClaimBlockIsBeforeEndBlock();
        // We cannot support bids at prices which cause TOTAL_SUPPLY * maxPrice to overflow a uint256
        MAX_BID_PRICE = type(uint256).max / TOTAL_SUPPLY;
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
        view
        returns (Checkpoint memory)
    {
        ValueX7 currencyRaisedQ96_X7;
        // If the clearing price is above the floor price, the auction is fully subscribed and the amount of
        // currency which will be raised is deterministic based on the initial supply schedule.
        if (_checkpoint.clearingPrice > FLOOR_PRICE) {
            // The currency raised over `deltaMps` percentage of the auction is simply the total supply
            // over than percentage multiplied by the current clearing price
            // note that currencyRaised is a ValueX7 because we DO NOT divide by MPS here,
            // and thus the value is 1e7 larger than the actual currency raised
            currencyRaisedQ96_X7 = ValueX7.wrap(TOTAL_SUPPLY).mulUint256(_checkpoint.clearingPrice * deltaMps);
            // There is a special case where the clearing price is at a tick boundary with bids.
            // In this case, we have to explicitly track the supply sold to that price since they are "partially filled"
            // and thus the amount of tokens sold to that price is <= to the collective demand at that price, since bidders at higher prices are prioritized.
            if (
                _checkpoint.clearingPrice % TICK_SPACING == 0
                    && _getTick(_checkpoint.clearingPrice).currencyDemandQ96 > 0
            ) {
                // The currencyRaisedAtClearingPrice is simply the demand at the clearing price multiplied by the price and the supply schedule
                // We should divide this by 1e7 (100%) to get the actualized currency raised, but to avoid intermediate division,
                // we upcast it into a X7X7 value to show that it has implicitly been scaled up by 1e7.
                // currencyRaisedAboveClearingPriceQ96_X7 is a ValueX7 because we DO NOT divide by MPS here
                ValueX7 currencyRaisedAboveClearingPriceQ96_X7 =
                    ValueX7.wrap($sumCurrencyDemandAboveClearingQ96 * deltaMps);
                ValueX7 currencyRaisedAtClearingPriceQ96_X7 =
                    currencyRaisedQ96_X7.sub(currencyRaisedAboveClearingPriceQ96_X7);
                // Update the cumulative value in the checkpoint which will be reset if the clearing price changes
                _checkpoint.currencyRaisedAtClearingPriceQ96_X7 =
                    _checkpoint.currencyRaisedAtClearingPriceQ96_X7.add(currencyRaisedAtClearingPriceQ96_X7);
            }
        }
        // In the case where the auction is not fully subscribed yet, we can only sell tokens equal to the current demand above the clearing price
        else {
            // We are behind schedule as the clearing price is still at the floor price
            // So we can only sell tokens to the current demand above the clearing price
            currencyRaisedQ96_X7 = ValueX7.wrap($sumCurrencyDemandAboveClearingQ96 * deltaMps);
        }
        _checkpoint.currencyRaisedQ96_X7 = _checkpoint.currencyRaisedQ96_X7.add(currencyRaisedQ96_X7);
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
    /// @param _sumCurrencyDemandAboveClearingQ96 The cumulative demand above the clearing price
    /// @return The new clearing price
    function _calculateNewClearingPrice(uint256 _tickLowerPrice, uint256 _sumCurrencyDemandAboveClearingQ96)
        internal
        view
        returns (uint256)
    {
        /**
         * The new clearing price is simply the ratio of the cumulative currency demand above the clearing price
         * to the total supply of the auction. It is multiplied by Q96 to return a value in terms of X96 form.
         *
         * The result of this may be lower than tickLowerPrice.
         * That just means that we can't sell at any price above and should sell at tickLowerPrice instead.
         */
        uint256 clearingPrice = _sumCurrencyDemandAboveClearingQ96.fullMulDivUp(FixedPoint96.Q96, TOTAL_SUPPLY_Q96);
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
        // If there are no more remaining mps in the auction, we don't need to iterate over ticks
        // and we can return the minimum clearing price above
        if (_checkpoint.remainingMpsInAuction() == 0) return minimumClearingPrice;

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
        Tick memory nextActiveTick = _getTick(nextActiveTickPrice_);
        while (
            nextActiveTickPrice_ != MAX_TICK_PTR
            // Loop while the currency amount above the clearing price is greater than the required currency at `nextActiveTickPrice_`
            && sumCurrencyDemandAboveClearingQ96_ >= TOTAL_SUPPLY * nextActiveTickPrice_
        ) {
            // Subtract the demand at the current nextActiveTick from the total demand
            sumCurrencyDemandAboveClearingQ96_ -= nextActiveTick.currencyDemandQ96;
            // Save the previous next active tick price
            minimumClearingPrice = nextActiveTickPrice_;
            // Advance to the next tick
            nextActiveTickPrice_ = nextActiveTick.next;
            nextActiveTick = _getTick(nextActiveTickPrice_);
            updateStateVariables = true;
        }
        // Set the values into storage if we found a new next active tick price
        if (updateStateVariables) {
            $sumCurrencyDemandAboveClearingQ96 = sumCurrencyDemandAboveClearingQ96_;
            $nextActiveTickPrice = nextActiveTickPrice_;
            emit NextActiveTickUpdated(nextActiveTickPrice_);
        }

        // Calculate the new clearing price
        uint256 clearingPrice = _calculateNewClearingPrice(minimumClearingPrice, sumCurrencyDemandAboveClearingQ96_);
        return clearingPrice;
    }

    /// @notice Internal function for checkpointing at a specific block number
    /// @dev This updates the state of the auction accounting for the bids placed after the last checkpoint
    ///      Checkpoints are created at the top of each block with a new bid and does NOT include that bid
    ///      Because of this, we need to calculate what the new state of the Auction should be before updating
    ///      purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingQ96` value
    /// @param blockNumber The block number to checkpoint at
    function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint) {
        if (blockNumber == $lastCheckpointedBlock) return latestCheckpoint();

        _checkpoint = latestCheckpoint();
        uint256 clearingPrice = _iterateOverTicksAndFindClearingPrice(_checkpoint);
        if (clearingPrice != _checkpoint.clearingPrice) {
            // Set the new clearing price
            _checkpoint.clearingPrice = clearingPrice;
            _checkpoint.currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(0);
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
            blockNumber, _checkpoint.clearingPrice, _checkpoint.currencyRaisedQ96_X7, _checkpoint.cumulativeMps
        );
    }

    /// @notice Return the final checkpoint of the auction
    /// @dev Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
    ///      any future calls to `step.mps` will return the mps of the last step in the auction
    function _getFinalCheckpoint() internal returns (Checkpoint memory) {
        return _unsafeCheckpoint(END_BLOCK);
    }

    function _submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        internal
        returns (uint256 bidId)
    {
        // Reject bids which would cause TOTAL_SUPPLY * maxPrice to overflow a uint256
        if (maxPrice > MAX_BID_PRICE) revert InvalidBidPriceTooHigh();

        Checkpoint memory _checkpoint = checkpoint();
        // Revert if there are no more tokens to be sold
        if (_checkpoint.remainingMpsInAuction() == 0) revert AuctionSoldOut();
        // We don't allow bids to be submitted at or below the clearing price
        if (maxPrice <= _checkpoint.clearingPrice) revert BidMustBeAboveClearingPrice();

        _initializeTickIfNeeded(prevTickPrice, maxPrice);

        VALIDATION_HOOK.handleValidate(maxPrice, amount, owner, msg.sender, hookData);
        // ClearingPrice will be set to floor price in checkpoint() if not set already
        // Scale the amount according to the rest of the supply schedule, accounting for past blocks
        // This is only used in demand related internal calculations
        Bid memory bid;
        uint256 amountQ96 = uint256(amount) << FixedPoint96.RESOLUTION;
        (bid, bidId) = _createBid(amountQ96, owner, maxPrice, _checkpoint.cumulativeMps);

        uint256 bidEffectiveAmountQ96 = bid.toEffectiveAmount();

        _updateTickDemand(maxPrice, bidEffectiveAmountQ96);

        $sumCurrencyDemandAboveClearingQ96 += bidEffectiveAmountQ96;

        // If the sumDemandAboveClearing becomes large enough to overflow a multiplication an X7 value, revert
        if ($sumCurrencyDemandAboveClearingQ96 >= ConstantsLib.X7_UPPER_BOUND) {
            revert InvalidBidUnableToClear();
        }

        emit BidSubmitted(bidId, owner, maxPrice, amount);
    }

    /// @notice Given a bid, tokens filled and refund, process the transfers and refund
    function _processExit(uint256 bidId, Bid memory bid, uint256 tokensFilled, uint256 refundQ96) internal {
        address _owner = bid.owner;

        if (tokensFilled == 0) {
            _deleteBid(bidId);
        } else {
            bid.tokensFilled = tokensFilled;
            bid.exitedBlock = uint64(block.number);
            _updateBid(bidId, bid);
        }

        uint256 refund = refundQ96 >> FixedPoint96.RESOLUTION;

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
    function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        public
        payable
        onlyActiveAuction
        returns (uint256)
    {
        // Bids cannot be submitted at the endBlock or after
        if (block.number >= END_BLOCK) revert AuctionIsOver();
        if (CURRENCY.isAddressZero()) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert CurrencyIsNotNative();
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(CURRENCY), msg.sender, address(this), amount);
        }
        return _submitBid(maxPrice, amount, owner, prevTickPrice, hookData);
    }

    /// @inheritdoc IAuction
    function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
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
            return _processExit(bidId, bid, 0, bid.amountQ96);
        }

        if (bid.maxPrice <= finalCheckpoint.clearingPrice) revert CannotExitBid();
        /// @dev Bid was fully filled and the auction is now over
        (uint256 tokensFilled, uint256 currencySpentQ96) =
            _accountFullyFilledCheckpoints(finalCheckpoint, _getCheckpoint(bid.startBlock), bid);

        _processExit(bidId, bid, tokensFilled, bid.amountQ96 - currencySpentQ96);
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
        uint256 currencySpentQ96;
        // If the lastFullyFilledCheckpoint is not 0, account for the fully filled checkpoints
        if (lastFullyFilledCheckpoint.clearingPrice > 0) {
            (tokensFilled, currencySpentQ96) =
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
            (uint256 partialTokensFilled, uint256 partialCurrencySpentQ96) = _accountPartiallyFilledCheckpoints(
                bid, _getTick(bidMaxPrice).currencyDemandQ96, upperCheckpoint.currencyRaisedAtClearingPriceQ96_X7
            );
            tokensFilled += partialTokensFilled;
            currencySpentQ96 += partialCurrencySpentQ96;
        }

        _processExit(bidId, bid, tokensFilled, bid.amountQ96 - currencySpentQ96);
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
        _sweepCurrency(finalCheckpoint.currencyRaisedQ96_X7.scaleDownToUint256() >> FixedPoint96.RESOLUTION);
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
    function sumCurrencyDemandAboveClearingQ96() external view override(IAuction) returns (uint256) {
        return $sumCurrencyDemandAboveClearingQ96;
    }
}
