// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStorage} from '../src/interfaces/IAuctionStorage.sol';
import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {IStepStorage} from '../src/interfaces/IStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from '../src/libraries/MaxBidPriceLib.sol';
import {PriceLib} from '../src/libraries/PriceLib.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {AuctionUnitTest} from './unit/AuctionUnitTest.sol';
import {Assertions} from './utils/Assertions.sol';
import {FuzzGenerators} from './utils/FuzzGenerators.sol';
import {FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {MockContinuousClearingAuction} from './utils/MockAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

interface IAuctionInvariantHarness {
    function initializeInvariantAuction(uint256 deploymentSeed) external returns (MockContinuousClearingAuction);
}

contract AuctionInvariantHandler is Test, Assertions {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for *;

    IAuctionInvariantHarness public harness;
    MockContinuousClearingAuction public mockAuction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint256 public BID_MIN_PRICE;
    bool public initialized;
    uint256 public deploymentSeed;

    uint256 internal constant TARGET_BIDS_PER_BLOCK = 8;

    // Ghost variables
    Checkpoint _checkpoint;
    uint256[] public bidIds;
    uint256 public bidCount;

    // Sum of the actual currency raised from all bids exited in the setup, less refunds
    uint256 public totalCurrencyRaised;

    struct Metrics {
        // Stats
        uint256 cnt_BidEarlyExited;
        uint256 cnt_BidExited;
        uint256 cnt_checkpoints;
        uint256 cnt_clearingPriceUpdated;
        uint256 cnt_untilTickPriceMAX_TICK_PTR;
        uint256 cnt_untilTickPrice;
        uint256 cnt_SubmitBidSkippedMaxPrice;
        uint256 cnt_SubmitBidSkippedSoldOut;
        uint256 cnt_SubmitBidSkippedAuctionFinished;
        uint256 cnt_NonGraduatedBidExited;
        uint256 cnt_ClaimTokensBatchNotGraduated;
        // Errors
        uint256 cnt_AuctionIsOverError;
        uint256 cnt_BidAmountTooSmallError;
        uint256 cnt_TickPriceNotIncreasingError;
        uint256 cnt_InvalidBidUnableToClearError;
        uint256 cnt_BidMustBeAboveClearingPriceError;
        uint256 cnt_NoBidToEarlyExitError;
        uint256 cnt_BidAlreadyExitedError;
    }

    Metrics internal metrics;

    constructor(IAuctionInvariantHarness _harness, address[] memory _actors) {
        harness = _harness;
        permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        actors = _actors;
    }

    modifier useDeployment(uint256 deploymentSeed_) {
        _ensureInitialized(deploymentSeed_);
        _;
    }

    function _ensureInitialized(uint256 deploymentSeed_) internal {
        if (initialized) return;

        deploymentSeed = deploymentSeed_;
        mockAuction = harness.initializeInvariantAuction(deploymentSeed_);
        currency = Currency.wrap(mockAuction.currency());
        token = IERC20Minimal(mockAuction.token());
        BID_MIN_PRICE = mockAuction.floorPrice() + mockAuction.tickSpacing();
        initialized = true;
    }

    modifier givenAuctionHasStarted() {
        if (block.number < mockAuction.startBlock()) {
            vm.roll(mockAuction.startBlock());
        }
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[_bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier validateCheckpoint() {
        _;
        Checkpoint memory checkpoint = mockAuction.latestCheckpoint();
        if (checkpoint.clearingPrice != 0) {
            assertGe(checkpoint.clearingPrice, mockAuction.floorPrice());
        }
        // Update metrics
        if (checkpoint.clearingPrice != _checkpoint.clearingPrice) {
            metrics.cnt_clearingPriceUpdated++;
        }
        // Reasonable way to check that a new checkpoint was created
        if (checkpoint.prev != _checkpoint.prev) {
            metrics.cnt_checkpoints++;
        }
        // Check that the clearing price is always increasing
        assertGe(checkpoint.clearingPrice, _checkpoint.clearingPrice, 'Checkpoint clearing price is not increasing');
        // Check that the cumulative variables are always increasing
        assertGe(checkpoint.cumulativeMps, _checkpoint.cumulativeMps, 'Checkpoint cumulative mps is not increasing');
        assertGe(
            checkpoint.cumulativeMpsPerPrice,
            _checkpoint.cumulativeMpsPerPrice,
            'Checkpoint cumulative mps per price is not increasing'
        );

        // Check that total cleared does not exceed the max tokens that can be sold in the auction so far
        assertLe(
            mockAuction.totalCleared(),
            (uint256(mockAuction.totalSupply()) * checkpoint.cumulativeMps) / ConstantsLib.MPS,
            'Total cleared exceeds the max tokens that can be sold in the auction so far'
        );

        // We can never have more sweepable tokens than the auction's balance
        assertLe(
            mockAuction.remainingSupply(),
            token.balanceOf(address(mockAuction)),
            'Sweepable tokens exceeds the auction\'s balance'
        );

        _checkpoint = checkpoint;
    }

    function _useNextBidPrice(uint256 clearingPrice, uint8 tickNumber) internal view returns (uint256, bool) {
        return
            FuzzGenerators.nextBidPrice(
                clearingPrice, mockAuction.tickSpacing(), mockAuction.MAX_BID_PRICE(), tickNumber
            );
    }

    /// @notice Generate random values for amount and max price given a desired resolved amount of tokens to purchase
    /// @dev Bounded by purchasing the total supply of tokens and some reasonable max price for bids to prevent overflow
    function _useAmountMaxPrice(uint128 amount, uint256 clearingPrice, uint8 tickNumber)
        internal
        view
        returns (uint128, uint256, bool)
    {
        (uint256 maxPrice, bool canSubmitAtHigherPrice) = _useNextBidPrice(clearingPrice, tickNumber);
        if (!canSubmitAtHigherPrice) return (0, 0, false);

        amount = FuzzGenerators.seededBidTokenAmount(amount);
        uint128 inputAmount = FuzzGenerators.inputAmountForTokens(amount, maxPrice);
        return (inputAmount, maxPrice, true);
    }

    /// @notice Find the first bid which can be early exited as of the stale checkpoint
    /// @return bidId The id of the first bid which can be early exited, or type(uint256).max if no bid can be exited
    function _useOutbidBidId() internal view returns (uint256) {
        // Partial exits before graduation are invalid by protocol design.
        if (!mockAuction.isGraduated()) return type(uint256).max;

        // Find first bid which can be exited as of the stale checkpoint
        // We could checkpoint again but no need, can use the stale checkpoint
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = mockAuction.bids(bidIds[i]);
            if (bid.exitedBlock != 0) continue;
            if (bid.maxPrice < _checkpoint.clearingPrice) return bidIds[i];
        }
        // If no bid can be exited, return type(uint256).max
        return type(uint256).max;
    }

    /// @notice Find the first bid which can be exited through exitBid
    /// @return bidId The id of the first exitable bid, or type(uint256).max if no bid can be exited
    function _useExitableBidId() internal returns (uint256) {
        if (bidCount == 0 || block.number < mockAuction.endBlock()) return type(uint256).max;

        mockAuction.checkpoint();
        bool isGraduated = mockAuction.isGraduated();
        uint256 clearingPrice = mockAuction.clearingPrice();

        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = bidIds[i];
            Bid memory bid = mockAuction.bids(bidId);
            if (bid.exitedBlock != 0) continue;
            if (!isGraduated || bid.maxPrice > clearingPrice) return bidId;
        }

        return type(uint256).max;
    }

    /// @notice Return the tick immediately equal to or below the given price
    function _getLowerTick(uint256 maxPrice) internal view returns (uint256) {
        uint256 _price = mockAuction.floorPrice();
        // If the bid price is less than the floor, we won't be able to find a prev pointer
        // So return 0 here and account for it in the test
        if (maxPrice <= _price) {
            return 0;
        }
        uint256 _cachedPrice = _price;
        while (_price < maxPrice) {
            // Set _price to the next price
            _price = mockAuction.ticks(_price).next;
            // If the next price is >= than our max price, break
            if (_price >= maxPrice) {
                break;
            }
            _cachedPrice = _price;
        }
        return _cachedPrice;
    }

    // TODO(ez): copy and pasted function from below
    /// Helper function to return the correct checkpoint hints for a partiallFilledBid
    function _getLowerUpperCheckpointHints(uint256 maxPrice) internal view returns (uint64 lower, uint64 upper) {
        uint64 currentBlock = mockAuction.lastCheckpointedBlock();

        // Traverse checkpoints from most recent to oldest
        while (currentBlock != 0) {
            Checkpoint memory checkpoint = mockAuction.checkpoints(currentBlock);

            // Find the first checkpoint with price > maxPrice (keep updating as we go backwards to get chronologically first)
            if (checkpoint.clearingPrice > maxPrice) {
                upper = currentBlock;
            }

            // Find the last checkpoint with price < maxPrice (first one encountered going backwards)
            if (checkpoint.clearingPrice < maxPrice && lower == 0) {
                lower = currentBlock;
            }

            currentBlock = checkpoint.prev;
        }

        return (lower, upper);
    }

    function _assertAveragePriceDoesNotExceedMax(
        uint256 amountQ96,
        uint256 tokensFilled,
        uint256 maxPrice,
        uint256 refundAmount
    ) internal pure {
        if (tokensFilled == 0) return;
        assertLe(
            (amountQ96 - uint256(refundAmount << FixedPoint96.RESOLUTION)) >> FixedPoint96.RESOLUTION,
            FixedPointMathLib.fullMulDiv(tokensFilled + 1, maxPrice, FixedPoint96.Q96) + 1e6,
            'ROUNDING INVARIANT VIOLATED: average purchase price exceeds maxPrice'
        );
    }

    function _handleSubmitBidRevert(
        bytes memory revertData,
        uint128 inputAmount,
        uint256 maxPrice,
        uint256 prevTickPrice
    ) internal {
        if (block.number >= mockAuction.endBlock()) {
            assertEq(revertData, abi.encodeWithSelector(IStepStorage.AuctionIsOver.selector));
            metrics.cnt_AuctionIsOverError++;
        } else if (
            bytes4(revertData)
                == bytes4(abi.encodeWithSelector(IContinuousClearingAuction.BidMustBeAboveClearingPrice.selector))
        ) {
            // See if we checkpoint, that the bid maxPrice would be at an invalid price
            mockAuction.checkpoint();
            // Because it reverted from BidMustBeAboveClearingPrice, we must assert that it should have
            assertLe(
                maxPrice,
                mockAuction.clearingPrice(),
                'Reverted with BidMustBeAboveClearingPrice but maxPrice is not above clearing price'
            );
            metrics.cnt_BidMustBeAboveClearingPriceError++;
        } else if (inputAmount == 0) {
            assertEq(revertData, abi.encodeWithSelector(IContinuousClearingAuction.BidAmountTooSmall.selector));
            metrics.cnt_BidAmountTooSmallError++;
        } else if (
            bytes4(revertData) == bytes4(abi.encodeWithSelector(IContinuousClearingAuction.AuctionSoldOut.selector))
        ) {
            metrics.cnt_SubmitBidSkippedSoldOut++;
        } else if (
            // If the prevTickPrice is 0, it could maybe be a race that the clearing price has increased since the bid was placed
            // This is handled in the else condition - so we exclude it here
            prevTickPrice == 0
                && bytes4(revertData)
                    != bytes4(abi.encodeWithSelector(IContinuousClearingAuction.BidMustBeAboveClearingPrice.selector))
        ) {
            assertEq(revertData, abi.encodeWithSelector(ITickStorage.TickPriceNotIncreasing.selector));
            metrics.cnt_TickPriceNotIncreasingError++;
        } else if (
            mockAuction.sumCurrencyDemandAboveClearingQ96()
                >= ConstantsLib.X7_UPPER_BOUND - (inputAmount * FixedPoint96.Q96 * ConstantsLib.MPS)
                    / (ConstantsLib.MPS - _checkpoint.cumulativeMps)
        ) {
            assertEq(revertData, abi.encodeWithSelector(IContinuousClearingAuction.InvalidBidUnableToClear.selector));
            metrics.cnt_InvalidBidUnableToClearError++;
        } else {
            // For race conditions or any errors that require additional calls to be made

            // Uncaught error so we bubble up the revert reason
            emit log_string('Invariant::handleSubmitBid: Uncaught error');
            assembly {
                revert(add(revertData, 0x20), mload(revertData))
            }
        }
    }

    /// @notice Roll the block number
    function handleRoll(uint256 deploymentSeed_, uint256 seed)
        public
        useDeployment(deploymentSeed_)
        givenAuctionHasStarted
    {
        if (block.number >= mockAuction.endBlock()) return;

        uint256 elapsedBlocks = block.number - mockAuction.startBlock() + 1;
        if (bidCount < elapsedBlocks * TARGET_BIDS_PER_BLOCK) return;

        // Keep early sequences bid-heavy, then advance faster once the book has meaningful demand.
        if (seed % 8 == 0) vm.roll(block.number + 1);
    }

    function handleCheckpoint(uint256 deploymentSeed_)
        public
        useDeployment(deploymentSeed_)
        validateCheckpoint
        givenAuctionHasStarted
    {
        mockAuction.checkpoint();
    }

    function handleForceIterateOverTicks(uint256 deploymentSeed_, uint8 tickNumber)
        public
        useDeployment(deploymentSeed_)
        givenAuctionHasStarted
    {
        uint256 untilTickPrice = mockAuction.MAX_TICK_PTR();
        uint256 nextActiveTickPrice = mockAuction.nextActiveTickPrice();

        if (nextActiveTickPrice != mockAuction.MAX_TICK_PTR()) {
            uint256 candidate = mockAuction.ticks(nextActiveTickPrice).next;
            uint256 hops = _bound(uint256(tickNumber), 0, 3);
            while (hops > 0 && candidate != mockAuction.MAX_TICK_PTR()) {
                uint256 nextCandidate = mockAuction.ticks(candidate).next;
                if (nextCandidate == mockAuction.MAX_TICK_PTR()) break;
                candidate = nextCandidate;
                hops--;
            }
            if (candidate != 0 && candidate != mockAuction.MAX_TICK_PTR()) {
                untilTickPrice = candidate;
            }
        }

        if (untilTickPrice == mockAuction.MAX_TICK_PTR()) {
            metrics.cnt_untilTickPriceMAX_TICK_PTR++;
        } else {
            metrics.cnt_untilTickPrice++;
        }
        mockAuction.forceIterateOverTicks(untilTickPrice);
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(uint256 deploymentSeed_, uint256 actorIndexSeed, uint128 bidAmount, uint8 tickNumber)
        public
        payable
        useDeployment(deploymentSeed_)
        useActor(actorIndexSeed)
        givenAuctionHasStarted
        validateCheckpoint
    {
        if (_checkpoint.cumulativeMps >= ConstantsLib.MPS) {
            metrics.cnt_SubmitBidSkippedAuctionFinished++;
            return;
        }
        if (ValueX7.unwrap(mockAuction.remainingSupplyQ96X7()) == 0) {
            metrics.cnt_SubmitBidSkippedSoldOut++;
            return;
        }

        (uint128 inputAmount, uint256 maxPrice, bool canSubmitAtHigherPrice) =
            _useAmountMaxPrice(bidAmount, _checkpoint.clearingPrice, tickNumber);
        if (!canSubmitAtHigherPrice) {
            metrics.cnt_SubmitBidSkippedMaxPrice++;
            return;
        }

        if (currency.isAddressZero()) {
            vm.deal(currentActor, inputAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, inputAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(mockAuction), type(uint160).max, type(uint48).max);
        }

        uint256 prevTickPrice = _getLowerTick(maxPrice);
        uint256 nextBidId = mockAuction.nextBidId();
        try mockAuction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, inputAmount, currentActor, prevTickPrice, bytes('')
        ) {
            bidIds.push(nextBidId);
            bidCount++;
        } catch (bytes memory revertData) {
            _handleSubmitBidRevert(revertData, inputAmount, maxPrice, prevTickPrice);
        }
    }

    function handleEarlyExitPartiallyFilledBid(uint256 deploymentSeed_, uint256 actorIndexSeed)
        public
        useDeployment(deploymentSeed_)
        useActor(actorIndexSeed)
    {
        uint256 outbidBidId = _useOutbidBidId();
        if (outbidBidId == type(uint256).max) {
            metrics.cnt_NoBidToEarlyExitError++;
            return;
        }
        Bid memory bid = mockAuction.bids(outbidBidId);
        if (bid.exitedBlock != 0) {
            metrics.cnt_BidAlreadyExitedError++;
            return;
        }

        assertLt(bid.maxPrice, _checkpoint.clearingPrice, 'Bid must be less than clearing price to early exit');
        (uint64 lower, uint64 upper) = _getLowerUpperCheckpointHints(bid.maxPrice);

        uint256 ownerBalanceBefore = bid.owner.balance;
        // Exit the outbid bid
        mockAuction.exitPartiallyFilledBid(outbidBidId, lower, upper);
        // Refetch the bid data, which now has `tokensFilled` set
        bid = mockAuction.bids(outbidBidId);
        uint256 maximumTokensFilled =
            FixedPointMathLib.min(BidLib.toEffectiveAmount(bid) / mockAuction.floorPrice(), mockAuction.totalSupply());
        assertLe(bid.tokensFilled, maximumTokensFilled, 'Bid tokens filled must be less than the maximum tokens filled');

        uint256 refundAmount = bid.owner.balance - ownerBalanceBefore;
        totalCurrencyRaised += bid.amountQ96 / FixedPoint96.Q96 - refundAmount;
        assertLe(
            refundAmount,
            bid.amountQ96 / FixedPoint96.Q96,
            'Bid owner can never be refunded more Currency than provided'
        );
        if (refundAmount == bid.amountQ96 / FixedPoint96.Q96) {
            assertEq(bid.tokensFilled, 0, 'Bid tokens filled must be 0 if bid is fully refunded');
        }
        _assertAveragePriceDoesNotExceedMax(bid.amountQ96, bid.tokensFilled, bid.maxPrice, refundAmount);

        metrics.cnt_BidEarlyExited++;
    }

    function handleExitBid(uint256 deploymentSeed_, uint256 actorIndexSeed)
        public
        useDeployment(deploymentSeed_)
        useActor(actorIndexSeed)
    {
        uint256 bidId = _useExitableBidId();
        if (bidId == type(uint256).max) return;

        Bid memory bid = mockAuction.bids(bidId);
        uint256 ownerBalanceBefore = bid.owner.balance;

        mockAuction.exitBid(bidId);

        bid = mockAuction.bids(bidId);
        uint256 refundAmount = bid.owner.balance - ownerBalanceBefore;
        totalCurrencyRaised += bid.amountQ96 / FixedPoint96.Q96 - refundAmount;

        assertEq(bid.exitedBlock, block.number);
        if (!mockAuction.isGraduated()) {
            assertEq(bid.tokensFilled, 0, 'Non-graduated auction exit must not fill tokens');
        }
        assertLe(
            refundAmount,
            bid.amountQ96 / FixedPoint96.Q96,
            'Bid owner can never be refunded more Currency than provided'
        );
        if (refundAmount == bid.amountQ96 / FixedPoint96.Q96) {
            assertEq(bid.tokensFilled, 0, 'Bid tokens filled must be 0 if bid is fully refunded');
        }
        _assertAveragePriceDoesNotExceedMax(bid.amountQ96, bid.tokensFilled, bid.maxPrice, refundAmount);

        uint256 maximumTokensFilled =
            FixedPointMathLib.min(BidLib.toEffectiveAmount(bid) / mockAuction.floorPrice(), mockAuction.totalSupply());
        assertLe(bid.tokensFilled, maximumTokensFilled, 'Bid tokens filled must be less than the maximum tokens filled');

        metrics.cnt_BidExited++;
        if (!mockAuction.isGraduated()) {
            metrics.cnt_NonGraduatedBidExited++;
        }
    }

    function printMetrics() public {
        emit log_string('==================== METRICS ====================');
        emit log_named_uint('bidCount', bidCount);
        emit log_named_uint('BidEarlyExited count', metrics.cnt_BidEarlyExited);
        emit log_named_uint('BidExited count', metrics.cnt_BidExited);
        emit log_named_uint('checkpoints count', metrics.cnt_checkpoints);
        emit log_named_uint('clearingPriceUpdated count', metrics.cnt_clearingPriceUpdated);
        emit log_named_uint('untilTickPriceMAX_TICK_PTR count', metrics.cnt_untilTickPriceMAX_TICK_PTR);
        emit log_named_uint('untilTickPrice count', metrics.cnt_untilTickPrice);
        emit log_named_uint('SubmitBidSkippedMaxPrice count', metrics.cnt_SubmitBidSkippedMaxPrice);
        emit log_named_uint('SubmitBidSkippedSoldOut count', metrics.cnt_SubmitBidSkippedSoldOut);
        emit log_named_uint('SubmitBidSkippedAuctionFinished count', metrics.cnt_SubmitBidSkippedAuctionFinished);
        emit log_named_uint('NonGraduatedBidExited count', metrics.cnt_NonGraduatedBidExited);
        emit log_named_uint('ClaimTokensBatchNotGraduated count', metrics.cnt_ClaimTokensBatchNotGraduated);
        emit log_named_uint('AuctionIsOverError count', metrics.cnt_AuctionIsOverError);
        emit log_named_uint('BidAmountTooSmallError count', metrics.cnt_BidAmountTooSmallError);
        emit log_named_uint('TickPriceNotIncreasingError count', metrics.cnt_TickPriceNotIncreasingError);
        emit log_named_uint('InvalidBidUnableToClearError count', metrics.cnt_InvalidBidUnableToClearError);
        emit log_named_uint('BidMustBeAboveClearingPriceError count', metrics.cnt_BidMustBeAboveClearingPriceError);
        emit log_named_uint('NoBidToEarlyExitError count', metrics.cnt_NoBidToEarlyExitError);
        emit log_named_uint('BidAlreadyExitedError count', metrics.cnt_BidAlreadyExitedError);
    }
}

abstract contract AuctionInvariantBase is AuctionUnitTest {
    AuctionInvariantHandler public handler;
    bool internal handlerInitializedAuction;

    function setUpInvariantAuction() internal {
        FuzzDeploymentParams memory bootstrapDeploymentParams = helper__seededInvariantDeploymentParams(0);
        setUpMockAuction(bootstrapDeploymentParams);

        address[] memory actors = new address[](2);
        actors[0] = alice;
        actors[1] = bob;

        handler = new AuctionInvariantHandler(IAuctionInvariantHarness(address(this)), actors);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = AuctionInvariantHandler.handleRoll.selector;
        selectors[1] = AuctionInvariantHandler.handleCheckpoint.selector;
        selectors[2] = AuctionInvariantHandler.handleForceIterateOverTicks.selector;
        selectors[3] = AuctionInvariantHandler.handleSubmitBid.selector;
        selectors[4] = AuctionInvariantHandler.handleEarlyExitPartiallyFilledBid.selector;
        selectors[5] = AuctionInvariantHandler.handleExitBid.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function initializeInvariantAuction(uint256 deploymentSeed) external returns (MockContinuousClearingAuction) {
        require(msg.sender == address(handler), 'ONLY_HANDLER');
        if (handlerInitializedAuction) return mockAuction;

        FuzzDeploymentParams memory fuzzDeploymentParams = helper__seededInvariantDeploymentParams(deploymentSeed);
        setUpMockAuction(fuzzDeploymentParams);
        logFuzzDeploymentParams($deploymentParams);

        handlerInitializedAuction = true;
        return mockAuction;
    }

    modifier printMetrics() {
        handler.printMetrics();
        _;
    }

    modifier givenAuctionIsOver() {
        vm.roll(mockAuction.endBlock());
        _;
    }

    modifier givenAuctionIsCheckpointed() {
        mockAuction.checkpoint();
        _;
    }

    function _printBalances() internal {
        emit log_string('==================== Auction Balances ====================');
        emit log_named_decimal_uint('currency balance', address(mockAuction).balance, 18);
        emit log_named_decimal_uint('token balance', token.balanceOf(address(mockAuction)), 18);
        emit log_string('==================== Funds Recipient Balances ====================');
        emit log_named_decimal_uint('currency balance', address(mockAuction.fundsRecipient()).balance, 18);
        emit log_string('==================== Tokens Recipient Balances ====================');
        emit log_named_decimal_uint('token balance', token.balanceOf(address(mockAuction.tokensRecipient())), 18);
    }

    function _printState() internal {
        emit log_string('==================== Auction State ====================');
        emit log_named_decimal_uint('totalSupply', mockAuction.totalSupply(), 18);
        emit log_named_uint('floorPrice', mockAuction.floorPrice());
        emit log_named_uint('tickSpacing', mockAuction.tickSpacing());
        emit log_named_uint('final clearing price', mockAuction.clearingPrice());
        emit log_named_decimal_uint('currencyRaised', mockAuction.currencyRaised(), 18);
    }

    /// Helper function to return the correct checkpoint hints for a partiallFilledBid
    function getLowerUpperCheckpointHints(uint256 maxPrice) public view returns (uint64 lower, uint64 upper) {
        uint64 currentBlock = mockAuction.lastCheckpointedBlock();

        // Traverse checkpoints from most recent to oldest
        while (currentBlock != 0) {
            Checkpoint memory checkpoint = mockAuction.checkpoints(currentBlock);

            // Find the first checkpoint with price > maxPrice (keep updating as we go backwards to get chronologically first)
            if (checkpoint.clearingPrice > maxPrice) {
                upper = currentBlock;
            }

            // Find the last checkpoint with price < maxPrice (first one encountered going backwards)
            if (checkpoint.clearingPrice < maxPrice && lower == 0) {
                lower = currentBlock;
            }

            currentBlock = checkpoint.prev;
        }

        return (lower, upper);
    }

    /// @notice Assert that the auction loses no more than 1e18 wei of currency or tokens
    function assertAcceptableDustBalances() internal view {
        assertApproxEqAbs(
            address(mockAuction).balance, 0, 1e18, 'Auction currency balance is not within 1e18 wei of zero'
        );
        assertApproxEqAbs(
            token.balanceOf(address(mockAuction)), 0, 1e18, 'Auction token balance is not within 1e18 wei of zero'
        );
    }

    /// @notice Exit and claim all outstanding bids on the auction
    /// @return totalCurrencyRaised The total currency raised from all bids exited and claimed
    function helper__exitAndClaimAllBids() internal returns (uint256 totalCurrencyRaised) {
        require(block.number >= mockAuction.endBlock(), 'helper__exitAndClaimAllBids::Auction must be over');
        require(
            mockAuction.lastCheckpointedBlock() == mockAuction.endBlock(),
            'helper__sweep::Auction must be checkpointed at endBlock'
        );

        uint256 clearingPrice = mockAuction.clearingPrice();

        uint256 bidCount = handler.bidCount();

        totalCurrencyRaised = handler.totalCurrencyRaised();
        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = handler.bidIds(i);
            Bid memory bid = mockAuction.bids(bidId);
            // Some bids may have been exited already as part of the setup run
            // Their total currency raised was already accounted for in handler.totalCurrencyRaised()
            if (bid.exitedBlock != 0) continue;

            uint256 currencyBalanceBefore = bid.owner.balance;
            if (bid.maxPrice > clearingPrice) {
                mockAuction.exitBid(bidId);
            } else {
                (uint64 lower, uint64 upper) = getLowerUpperCheckpointHints(bid.maxPrice);
                mockAuction.exitPartiallyFilledBid(bidId, lower, upper);
            }
            uint256 refundAmount = bid.owner.balance - currencyBalanceBefore;
            totalCurrencyRaised += bid.amountQ96 / FixedPoint96.Q96 - refundAmount;

            // can never gain more Currency than provided
            assertLe(
                refundAmount,
                bid.amountQ96 / FixedPoint96.Q96,
                'Bid owner can never be refunded more Currency than provided'
            );

            // Bid might be deleted if tokensFilled = 0
            bid = mockAuction.bids(bidId);
            if (bid.tokensFilled == 0) continue;

            // UNIVERSAL INVARIANT: Average purchase price must never exceed maxPrice
            // This ensures bidders never pay more per token than their bid price
            // Works for both fully-filled and partially-filled bids

            // Mathematical form: avgPrice = currencySpent / tokensFilled ≤ maxPrice
            // Rearranged: currencySpent ≤ tokensFilled × maxPrice

            uint256 currencySpent =
                (bid.amountQ96 - uint256(refundAmount << FixedPoint96.RESOLUTION)) >> FixedPoint96.RESOLUTION;

            // Compare against the rounded up value of tokensFilled since we round against the user
            uint256 tokensFilledRoundedUp = bid.tokensFilled > 0 ? bid.tokensFilled + 1 : bid.tokensFilled;
            // Compare against the rounded down value of currencySpent since we round against the user
            uint256 maxValueAtBidPrice =
                FixedPointMathLib.fullMulDiv(tokensFilledRoundedUp, bid.maxPrice, FixedPoint96.Q96);

            assertLe(
                currencySpent,
                maxValueAtBidPrice + 1e6,
                string.concat(
                    'ROUNDING INVARIANT VIOLATED: Bid ',
                    vm.toString(bidId),
                    ' - average purchase price exceeds maxPrice'
                )
            );

            assertEq(bid.exitedBlock, block.number);

            uint256 maximumTokensFilled = FixedPointMathLib.min(
                BidLib.toEffectiveAmount(bid) / mockAuction.floorPrice(), mockAuction.totalSupply()
            );
            assertLe(
                bid.tokensFilled, maximumTokensFilled, 'Bid tokens filled must be less than the maximum tokens filled'
            );
        }

        vm.roll(mockAuction.claimBlock());
        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = handler.bidIds(i);
            Bid memory bid = mockAuction.bids(bidId);
            if (bid.tokensFilled == 0) continue;
            assertNotEq(bid.exitedBlock, 0);

            uint256 ownerBalanceBefore = token.balanceOf(bid.owner);
            vm.expectEmit(true, true, false, false);
            emit IContinuousClearingAuction.TokensClaimed(bidId, bid.owner, bid.tokensFilled);
            mockAuction.claimTokens(bidId);
            // Assert that the owner received the tokens
            assertEq(token.balanceOf(bid.owner), ownerBalanceBefore + bid.tokensFilled);

            bid = mockAuction.bids(bidId);
            assertEq(bid.tokensFilled, 0);
        }

        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();

        emit log_string('==================== AFTER EXIT AND CLAIM TOKENS ====================');
        emit log_named_uint('bidCount', handler.bidCount());
        emit log_named_uint('auction duration (blocks)', mockAuction.endBlock() - mockAuction.startBlock());
        emit log_named_decimal_uint('auction floor price', mockAuction.floorPrice(), 96);
        emit log_named_decimal_uint('auction final clearing price', mockAuction.clearingPrice(), 96);
        emit log_named_decimal_uint('auction total supply', mockAuction.totalSupply(), 18);
        emit log_named_decimal_uint('auction totalCleared', mockAuction.totalCleared(), 18);
        emit log_named_decimal_uint('auction remaining token balance', token.balanceOf(address(mockAuction)), 18);
        emit log_named_decimal_uint('auction remaining currency balance', address(mockAuction).balance, 18);
        emit log_named_decimal_uint('actualCurrencyRaised', totalCurrencyRaised, 18);
        emit log_named_decimal_uint('expectedCurrencyRaised', expectedCurrencyRaised, 18);

        return totalCurrencyRaised;
    }

    function helper__sweep() internal {
        require(block.number >= mockAuction.endBlock(), 'helper__sweep::Auction must be over');
        require(
            mockAuction.lastCheckpointedBlock() == mockAuction.endBlock(),
            'helper__sweep::Auction must be checkpointed at endBlock'
        );

        // Get the expected currency raised from the auction
        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();

        // We can always sweep unsold tokens regardless of graduation status
        vm.prank(mockAuction.tokensRecipient());
        mockAuction.sweepUnsoldTokens();

        if (mockAuction.isGraduated()) {
            emit log_string('==================== GRADUATED AUCTION ====================');
            assertLe(
                expectedCurrencyRaised,
                address(mockAuction).balance,
                'Expected currency raised is greater than auction balance'
            );
            // Sweep the currency
            vm.expectEmit(true, true, true, true);
            emit IAuctionStorage.CurrencySwept(mockAuction.fundsRecipient(), expectedCurrencyRaised);
            vm.prank(mockAuction.fundsRecipient());
            mockAuction.sweepCurrency();
            // Assert that the funds recipient received the currency
            assertEq(
                mockAuction.fundsRecipient().balance,
                expectedCurrencyRaised,
                'Funds recipient balance does not match expected currency raised'
            );
        } else {
            emit log_string('==================== NOT GRADUATED AUCTION ====================');
            vm.prank(mockAuction.fundsRecipient());
            vm.expectRevert(IAuctionStorage.NotGraduated.selector);
            mockAuction.sweepCurrency();
            // At this point we know all bids have been exited so auction balance should be zero
            assertEq(address(mockAuction).balance, 0, 'Auction balance is not zero at end of auction');
        }
    }

    function invariant_canAlwaysCheckpointDuringAuction() public printMetrics {
        if (block.number >= mockAuction.startBlock() && block.number < mockAuction.claimBlock()) {
            mockAuction.checkpoint();
        }
    }

    function invariant_totalClearedNeverExceedsTotalSupply() public printMetrics {
        assertLe(
            ValueX7.unwrap(mockAuction.totalClearedQ96X7()),
            ValueX7.unwrap(mockAuction.totalSupplyQ96X7()),
            'Total cleared exceeds total supply'
        );
    }

    function invariant_clearingPriceIsMaximumPossible() public printMetrics {
        // Not applicable before auction starts
        if (block.number < mockAuction.startBlock()) return;
        // Checkpoint to ensure all state is up to date
        mockAuction.checkpoint();
        uint256 clearingPrice = mockAuction.clearingPrice();
        // Not applicable at floor price
        if (clearingPrice == mockAuction.floorPrice()) return;
        // Not applicable at tick boundary (partial fills are complex)
        if (clearingPrice % mockAuction.tickSpacing() == 0) return;

        // The clearing price should be the maximum possible price for which remaining supply
        // can be sold to demand at or above the clearing price
        uint256 remainingSupplyQ96X7 = ValueX7.unwrap(mockAuction.remainingSupplyQ96X7());
        uint256 sumDemandQ96 = mockAuction.sumCurrencyDemandAboveClearingQ96();
        uint256 purchasableSupplyQ96X7 = PriceLib.toTokensRoundingUp(sumDemandQ96 * ConstantsLib.MPS, clearingPrice);

        // The invariant MAY be broken IF the clearingPrice was rounded up by one wei.
        if (purchasableSupplyQ96X7 < remainingSupplyQ96X7) {
            uint256 allowableBuffer = 1 * (sumDemandQ96 * ConstantsLib.MPS);
            assertGe(purchasableSupplyQ96X7 + allowableBuffer, remainingSupplyQ96X7);
        } else {
            // As long as the purchasable supply is greater than or equal to the remaining supply, the invariant holds
            // If it were less than, it would mean that the clearing price is not high enough to sell all the remaining supply
            assertGe(purchasableSupplyQ96X7, remainingSupplyQ96X7);
        }
    }

    function helper__exitAllBidsInNonGraduatedAuction() internal returns (uint256 totalRefunded) {
        require(
            block.number >= mockAuction.endBlock(), 'helper__exitAllBidsInNonGraduatedAuction::Auction must be over'
        );
        require(
            mockAuction.lastCheckpointedBlock() == mockAuction.endBlock(),
            'helper__exitAllBidsInNonGraduatedAuction::Auction must be checkpointed at endBlock'
        );
        assertFalse(mockAuction.isGraduated());

        uint256 bidCount = handler.bidCount();
        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = handler.bidIds(i);
            Bid memory bid = mockAuction.bids(bidId);
            if (bid.exitedBlock != 0) continue;

            uint256 ownerBalanceBefore = bid.owner.balance;
            mockAuction.exitBid(bidId);

            bid = mockAuction.bids(bidId);
            uint256 refundAmount = bid.owner.balance - ownerBalanceBefore;
            totalRefunded += refundAmount;

            assertEq(bid.exitedBlock, block.number);
            assertEq(bid.tokensFilled, 0, 'Non-graduated bid exit must not fill tokens');
            assertEq(refundAmount, bid.amountQ96 / FixedPoint96.Q96, 'Non-graduated bid must be fully refunded');
        }
    }

    function helper__sweepUnsoldTokensInNonGraduatedAuction() internal {
        uint256 tokensRecipientBalanceBefore = token.balanceOf(mockAuction.tokensRecipient());
        vm.prank(mockAuction.tokensRecipient());
        mockAuction.sweepUnsoldTokens();
        assertEq(
            token.balanceOf(mockAuction.tokensRecipient()), tokensRecipientBalanceBefore + mockAuction.totalSupply()
        );
        assertEq(token.balanceOf(address(mockAuction)), 0);

        vm.prank(mockAuction.fundsRecipient());
        vm.expectRevert(IAuctionStorage.NotGraduated.selector);
        mockAuction.sweepCurrency();
    }

    function helper__assertClaimsRevertWhenNotGraduated() internal {
        vm.roll(mockAuction.claimBlock());

        uint256 bidCount = handler.bidCount();
        uint256[] memory bidIds = new uint256[](bidCount);
        for (uint256 i = 0; i < bidCount; i++) {
            bidIds[i] = handler.bidIds(i);
            vm.expectRevert(IAuctionStorage.NotGraduated.selector);
            mockAuction.claimTokens(bidIds[i]);
        }

        vm.expectRevert(IAuctionStorage.NotGraduated.selector);
        mockAuction.claimTokensBatch(alice, bidIds);
    }
}

contract AuctionInvariantTest is AuctionInvariantBase {
    function setUp() public {
        setUpInvariantAuction();
    }

    function test_invariantAuctionInitializesFromHandlerSeed() public {
        MockContinuousClearingAuction bootstrapAuction = mockAuction;
        assertNotEq(address(bootstrapAuction), address(0));
        assertFalse(handler.initialized());

        handler.handleCheckpoint(1);

        assertNotEq(address(mockAuction), address(0));
        assertNotEq(address(mockAuction), address(bootstrapAuction));
        assertEq(address(handler.mockAuction()), address(mockAuction));
        assertEq(address(handler.token()), address(token));
        assertEq(handler.BID_MIN_PRICE(), mockAuction.floorPrice() + mockAuction.tickSpacing());
        assertEq(handler.deploymentSeed(), 1);
    }

    function test_seededInvariantTickSpacingUsesRealisticFloorRatios() public {
        for (uint256 i = 0; i < 32; i++) {
            FuzzDeploymentParams memory fuzzDeploymentParams = helper__seededInvariantDeploymentParams(i);
            uint256 floorPrice = fuzzDeploymentParams.auctionParams.floorPrice;
            uint256 tickSpacing = fuzzDeploymentParams.auctionParams.tickSpacing;

            assertEq(floorPrice % tickSpacing, 0);
            assertLe(floorPrice + tickSpacing, MaxBidPriceLib.maxBidPrice(fuzzDeploymentParams.totalSupply));

            uint256 tickSpacingBps = (tickSpacing * 10_000) / floorPrice;
            assertTrue(
                tickSpacingBps == 1 || tickSpacingBps == 100 || tickSpacingBps == 1000 || tickSpacingBps == 10_000
            );
        }
    }

    function test_fuzzGeneratorsCanBeUsedWithoutAuctionBaseStorage() public view {
        FuzzDeploymentParams memory fuzzDeploymentParams = FuzzGenerators.seededDeploymentParams(
            1, ETH_SENTINEL, tokensRecipient, fundsRecipient, address(0), block.number
        );
        uint128 bidTokenAmount = FuzzGenerators.seededBidTokenAmount(42);
        (uint256 maxPrice, bool canBid) = FuzzGenerators.nextBidPrice(
            fuzzDeploymentParams.auctionParams.floorPrice,
            fuzzDeploymentParams.auctionParams.tickSpacing,
            MaxBidPriceLib.maxBidPrice(fuzzDeploymentParams.totalSupply),
            3
        );

        assertTrue(canBid);
        assertGt(bidTokenAmount, 0);
        assertGt(maxPrice, fuzzDeploymentParams.auctionParams.floorPrice);
        assertEq(maxPrice % fuzzDeploymentParams.auctionParams.tickSpacing, 0);
    }

    function test_fuzzGeneratorsIncludeBidAmountValidationExtremes() public pure {
        assertEq(FuzzGenerators.seededBidTokenAmount(0), 0);
        assertEq(FuzzGenerators.seededBidTokenAmount(1), 1);
        assertEq(FuzzGenerators.seededBidTokenAmount(6), type(uint128).max);
    }

    function test_handleRollWaitsForBidDensity() public {
        handler.handleRoll(1, 0);

        assertEq(block.number, mockAuction.startBlock());
        assertEq(handler.bidCount(), 0);
    }

    function invariant_canSweep_thenExitAndClaimAllBids()
        public
        printMetrics
        givenAuctionIsOver
        givenAuctionIsCheckpointed
    {
        if (!mockAuction.isGraduated()) return;

        // Sweep first
        helper__sweep();
        // Then exit and claim all bids
        uint256 totalCurrencyRaised = helper__exitAndClaimAllBids();

        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();
        assertLe(
            expectedCurrencyRaised,
            totalCurrencyRaised,
            'Expected currency raised is greater than total currency raised'
        );

        _printBalances();
        assertAcceptableDustBalances();
        _printState();
    }

    function invariant_canExitAndClaimAllBids_thenSweep()
        public
        printMetrics
        givenAuctionIsOver
        givenAuctionIsCheckpointed
    {
        if (!mockAuction.isGraduated()) return;

        // Exit and claim all bids first
        uint256 totalCurrencyRaised = helper__exitAndClaimAllBids();
        // Then sweep
        helper__sweep();

        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();
        assertLe(
            expectedCurrencyRaised,
            totalCurrencyRaised,
            'Expected currency raised is greater than total currency raised'
        );

        _printBalances();
        assertAcceptableDustBalances();
        _printState();
    }

    function invariant_nonGraduatedAuctionRefundsBidsAndSweepsAllTokens()
        public
        printMetrics
        givenAuctionIsOver
        givenAuctionIsCheckpointed
    {
        if (mockAuction.isGraduated()) return;

        assertFalse(mockAuction.isGraduated());

        helper__sweepUnsoldTokensInNonGraduatedAuction();
        helper__exitAllBidsInNonGraduatedAuction();
        assertEq(address(mockAuction).balance, 0, 'Non-graduated auction must refund all bid currency');
        helper__assertClaimsRevertWhenNotGraduated();

        _printBalances();
        _printState();
    }

    /// @notice The clearing price must always remain between the floor price and MAX_BID_PRICE.
    /// @dev Floor is the immutable lower bound set at construction; MAX_BID_PRICE is the cap derived from total supply.
    function invariant_clearingPriceWithinBounds() public view {
        // Ensure auction is checkpointed
        mockAuction.checkpoint();
        uint256 cp = mockAuction.clearingPrice();
        assertGe(cp, mockAuction.floorPrice(), 'Clearing price below floor price');
        assertLe(cp, mockAuction.MAX_BID_PRICE(), 'Clearing price above MAX_BID_PRICE');
    }

    /// @notice After a full checkpoint, the next active tick price must be strictly above the clearing price.
    /// @dev `forceIterateOverTicks` may legitimately leave `nextActiveTickPrice` below the new clearing price
    ///      because it can stop early at a caller-supplied `_untilTickPrice`. A real checkpoint always iterates
    ///      to `MAX_TICK_PTR`, so the invariant must hold post-checkpoint.
    function invariant_nextActiveTickPriceAboveClearingAfterCheckpoint() public {
        if (block.number < mockAuction.startBlock() || block.number >= mockAuction.claimBlock()) return;
        mockAuction.checkpoint();
        uint256 nextActiveTickPrice = mockAuction.nextActiveTickPrice();
        if (nextActiveTickPrice == mockAuction.MAX_TICK_PTR()) return;
        assertGt(
            nextActiveTickPrice,
            mockAuction.clearingPrice(),
            'Next active tick must be strictly above clearing after checkpoint'
        );
    }

    /// @notice The running sum of demand above clearing must always stay below the X7 upper bound.
    /// @dev Exceeding this bound would cause subsequent bids to revert with `InvalidBidUnableToClear`.
    function invariant_sumDemandBelowUpperBound() public view {
        assertLt(
            mockAuction.sumCurrencyDemandAboveClearingQ96(),
            ConstantsLib.X7_UPPER_BOUND,
            'Sum demand above clearing must stay below X7 upper bound'
        );
    }

    /// @notice The auction's currency balance must cover the principal of every unexited bid.
    /// @dev Currency only leaves the auction via refunds on exit or via `sweepCurrency`. The handler exercises
    ///      `exitPartiallyFilledBid` (early exit during the auction), so for unexited bids the full principal
    ///      should still be sitting in the contract along with the unrefunded portion of any exited bids.
    function invariant_auctionBalanceCoversUnexitedBids() public view {
        if (mockAuction.currency() != address(0)) return;
        if (mockAuction.sweepCurrencyBlock() != 0) return;

        uint256 bidCount = handler.bidCount();
        uint256 unexitedPrincipal;
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = mockAuction.bids(handler.bidIds(i));
            if (bid.exitedBlock != 0) continue;
            unexitedPrincipal += bid.amountQ96 / FixedPoint96.Q96;
        }
        assertGe(
            address(mockAuction).balance,
            unexitedPrincipal,
            'Auction balance must cover the principal of all unexited bids'
        );
    }

    /// @notice `currencyRaised` is bounded by `totalSupply * clearingPrice / Q96`.
    /// @dev We can never raise more currency than what selling the total supply at clearing price would yield
    ///      (clearing price is the price at which we cleared the auction so far).
    function invariant_currencyRaisedBoundedByMaxRaisable() public view {
        uint256 maxRaisable = FixedPointMathLib.fullMulDiv(
            uint256(mockAuction.totalSupply()), mockAuction.clearingPrice(), FixedPoint96.Q96
        );
        // Allow 1 wei rounding tolerance since clearing price is rounded up
        assertLe(mockAuction.currencyRaised(), maxRaisable + 1, 'Currency raised exceeds theoretical maximum');
    }
}

/// @notice Focused PoC for the `invariant_clearingPriceWithinBounds` failure.
/// @dev Demonstrates that `forceIterateOverTicks(_untilTickPrice)` can set `$clearingPrice` to a value
///      strictly greater than `MAX_BID_PRICE` when `_untilTickPrice` is a partial limit (not `MAX_TICK_PTR`)
///      and residual demand from ticks at/above that limit is large enough.
///
///      The contract never clamps the value returned by `_iterateOverTicksAndFindClearingPrice` to
///      `MAX_BID_PRICE`. The cap is only enforced on incoming bid prices (`_submitBid`), not on the
///      *computed* clearing price.
contract ClearingPriceOverflowPoC is AuctionUnitTest {
    function setUp() public {
        setUpMockAuction();
    }

    /// @notice forceIterateOverTicks with a partial `_untilTickPrice` can raise `$clearingPrice` above `MAX_BID_PRICE`.
    function test_clearingPriceCanExceedMaxBidPriceViaForceIterate() public {
        uint256 floor = mockAuction.floorPrice();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 maxBidPrice = mockAuction.MAX_BID_PRICE();

        vm.roll(mockAuction.startBlock());

        // tickA: a low tick (just above floor)
        // tickB: a high tick (highest tick boundary <= MAX_BID_PRICE)
        uint256 tickA = floor + tickSpacing;
        uint256 tickB = maxBidPrice - (maxBidPrice % tickSpacing);
        require(tickB > tickA + tickSpacing, 'PoC setup: pick a config with room between tickA and tickB');

        // Tiny bid at tickA — its only purpose is to give the iteration a tick to consume before stopping
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        mockAuction.submitBid{value: 1 ether}(tickA, 1 ether, alice, floor, bytes(''));

        // Massive bid at tickB — provides the residual demand left after the partial iteration
        uint128 hugeAmount = type(uint128).max;
        vm.deal(bob, hugeAmount);
        vm.prank(bob);
        mockAuction.submitBid{value: hugeAmount}(tickB, hugeAmount, bob, tickA, bytes(''));

        // After both bids: nextActiveTickPrice == tickA, sumDemand = tickA's + tickB's demand
        assertEq(mockAuction.nextActiveTickPrice(), tickA, 'precondition: nextActiveTickPrice == tickA');

        // Force-iterate up to (but not including) tickB.
        // Loop processes tickA (subtracts its demand, advances to tickB), then exits because
        // `nextActiveTickPrice_ == _untilTickPrice`. Residual demand is tickB's huge demand.
        // `clearingPrice_ = toPriceCeiling(residual demand, supply, mps)` — no clamp to MAX_BID_PRICE.
        mockAuction.forceIterateOverTicks(tickB);

        uint256 cp = mockAuction.clearingPrice();
        emit log_named_uint('MAX_BID_PRICE', maxBidPrice);
        emit log_named_uint('clearingPrice', cp);
        emit log_named_uint('nextActiveTickPrice', mockAuction.nextActiveTickPrice());

        assertGt(cp, maxBidPrice, 'Clearing price exceeds MAX_BID_PRICE - invariant violated');

        // Downstream effect 1: All subsequent bids revert with BidMustBeAboveClearingPrice,
        // because no valid bid maxPrice (<= MAX_BID_PRICE < clearingPrice) can satisfy the precondition.
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(IContinuousClearingAuction.BidMustBeAboveClearingPrice.selector);
        mockAuction.submitBid{value: 1 ether}(tickB, 1 ether, alice, tickA, bytes(''));

        // Downstream effect 2: A real checkpoint at a fresh block continues iteration from tickB and
        // resolves the inconsistency — clearing settles back at or below MAX_BID_PRICE.
        vm.roll(block.number + 1);
        mockAuction.checkpoint();
        assertLe(mockAuction.clearingPrice(), maxBidPrice, 'Next-block checkpoint resolves the inconsistency');
    }
}
