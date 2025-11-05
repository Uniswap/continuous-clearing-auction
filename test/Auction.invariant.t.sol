// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {IStepStorage} from '../src/interfaces/IStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionUnitTest} from './unit/AuctionUnitTest.sol';
import {Assertions} from './utils/Assertions.sol';
import {MockContinuousClearingAuction} from './utils/MockAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

contract AuctionInvariantHandler is Test, Assertions {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for *;
    using ValueX7Lib for *;

    MockContinuousClearingAuction public mockAuction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint256 public BID_MIN_PRICE;

    // Ghost variables
    Checkpoint _checkpoint;
    uint256[] public bidIds;
    uint256 public bidCount;

    // Sum of the actual currency raised from all bids exited in the setup, less refunds
    uint256 public totalCurrencyRaised;

    struct Metrics {
        // Stats
        uint256 cnt_BidEarlyExited;
        uint256 cnt_checkpoints;
        uint256 cnt_clearingPriceUpdated;
        // Errors
        uint256 cnt_AuctionIsOverError;
        uint256 cnt_BidAmountTooSmallError;
        uint256 cnt_TickPriceNotIncreasingError;
        uint256 cnt_InvalidBidUnableToClearError;
        uint256 cnt_BidMustBeAboveClearingPriceError;
        uint256 cnt_NoBidToEarlyExitError;
        uint256 cnt_BidAlreadyExitedError;
    }

    Metrics public metrics;

    constructor(MockContinuousClearingAuction _auction, address[] memory _actors) {
        mockAuction = _auction;
        permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        currency = mockAuction.currency();
        token = mockAuction.token();
        actors = _actors;

        BID_MIN_PRICE = mockAuction.floorPrice() + mockAuction.tickSpacing();
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
            (uint256(mockAuction.totalSupply()) * checkpoint.cumulativeMps) / ConstantsLib.MPS
        );

        // We can never have more sweepable tokens than the auction's balance
        assertLe(mockAuction.sweepableTokens(), token.balanceOf(address(mockAuction)));

        _checkpoint = checkpoint;
    }

    /// @notice Generate random values for amount and max price given a desired resolved amount of tokens to purchase
    /// @dev Bounded by purchasing the total supply of tokens and some reasonable max price for bids to prevent overflow
    function _useAmountMaxPrice(uint128 amount, uint256 clearingPrice, uint8 tickNumber)
        internal
        view
        returns (uint128, uint256)
    {
        tickNumber = uint8(_bound(tickNumber, 1, uint256(type(uint8).max)));
        uint256 tickNumberPrice = mockAuction.floorPrice() + tickNumber * mockAuction.tickSpacing();
        vm.assume(clearingPrice + mockAuction.tickSpacing() < type(uint256).max / mockAuction.totalSupply());
        uint256 maxPrice = _bound(
            tickNumberPrice, clearingPrice + mockAuction.tickSpacing(), type(uint256).max / mockAuction.totalSupply()
        );
        // Round down to the nearest tick boundary
        maxPrice -= (maxPrice % mockAuction.tickSpacing());
        uint128 inputAmount;
        if (amount > (type(uint128).max * FixedPoint96.Q96) / maxPrice) {
            inputAmount = type(uint128).max;
        } else {
            inputAmount = SafeCastLib.toUint128(amount.fullMulDivUp(maxPrice, FixedPoint96.Q96));
        }
        return (inputAmount, maxPrice);
    }

    /// @notice Find the first bid which can be early exited as of the stale checkpoint
    /// @return bidId The id of the first bid which can be early exited, or type(uint256).max if no bid can be exited
    function _useOutbidBidId() internal returns (uint256) {
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

    /// @notice Roll the block number
    function handleRoll(uint256 seed) public {
        // Roll 10% of the time to ensure that we can submit enough bids given the block duration of the auction
        if (seed % 10 == 0) vm.roll(block.number + 1);
    }

    function handleCheckpoint() public validateCheckpoint {
        if (block.number < mockAuction.startBlock()) {
            vm.expectRevert(IContinuousClearingAuction.AuctionNotStarted.selector);
        }
        mockAuction.checkpoint();
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(uint256 actorIndexSeed, uint128 bidAmount, uint8 tickNumber)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        // If we are not at the start of the auction - lets roll forward to it
        if (block.number < mockAuction.startBlock()) {
            vm.roll(mockAuction.startBlock());
        }

        (uint128 inputAmount, uint256 maxPrice) = _useAmountMaxPrice(bidAmount, _checkpoint.clearingPrice, tickNumber);
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
        emit log_named_decimal_uint('submitting bid with amount', inputAmount, 18);
        try mockAuction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, inputAmount, currentActor, prevTickPrice, bytes('')
        ) {
            bidIds.push(nextBidId);
            bidCount++;
        } catch (bytes memory revertData) {
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
                assertLe(maxPrice, mockAuction.clearingPrice());
                metrics.cnt_BidMustBeAboveClearingPriceError++;
            } else if (
                // If the prevTickPrice is 0, it could maybe be a race that the clearing price has increased since the bid was placed
                // This is handled in the else condition - so we exclude it here
                prevTickPrice == 0
                    && bytes4(revertData)
                        != bytes4(
                            abi.encodeWithSelector(IContinuousClearingAuction.BidMustBeAboveClearingPrice.selector)
                        )
            ) {
                assertEq(revertData, abi.encodeWithSelector(ITickStorage.TickPriceNotIncreasing.selector));
                metrics.cnt_TickPriceNotIncreasingError++;
            } else if (inputAmount == 0) {
                assertEq(revertData, abi.encodeWithSelector(IContinuousClearingAuction.BidAmountTooSmall.selector));
                metrics.cnt_BidAmountTooSmallError++;
            } else if (
                mockAuction.sumCurrencyDemandAboveClearingQ96()
                    >= ConstantsLib.X7_UPPER_BOUND - (inputAmount * FixedPoint96.Q96 * ConstantsLib.MPS)
                        / (ConstantsLib.MPS - _checkpoint.cumulativeMps)
            ) {
                assertEq(
                    revertData, abi.encodeWithSelector(IContinuousClearingAuction.InvalidBidUnableToClear.selector)
                );
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
    }

    function handleEarlyExitPartiallyFilledBid(uint256 actorIndexSeed) public useActor(actorIndexSeed) {
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

        metrics.cnt_BidEarlyExited++;
    }

    function printMetrics() public {
        emit log_string('==================== METRICS ====================');
        emit log_named_uint('bidCount', bidCount);
        emit log_named_uint('BidEarlyExited count', metrics.cnt_BidEarlyExited);
        emit log_named_uint('checkpoints count', metrics.cnt_checkpoints);
        emit log_named_uint('clearingPriceUpdated count', metrics.cnt_clearingPriceUpdated);
        emit log_named_uint('AuctionIsOverError count', metrics.cnt_AuctionIsOverError);
        emit log_named_uint('BidAmountTooSmallError count', metrics.cnt_BidAmountTooSmallError);
        emit log_named_uint('TickPriceNotIncreasingError count', metrics.cnt_TickPriceNotIncreasingError);
        emit log_named_uint('InvalidBidUnableToClearError count', metrics.cnt_InvalidBidUnableToClearError);
        emit log_named_uint('BidMustBeAboveClearingPriceError count', metrics.cnt_BidMustBeAboveClearingPriceError);
        emit log_named_uint('NoBidToEarlyExitError count', metrics.cnt_NoBidToEarlyExitError);
        emit log_named_uint('BidAlreadyExitedError count', metrics.cnt_BidAlreadyExitedError);
    }
}

contract AuctionInvariantTest is AuctionUnitTest {
    AuctionInvariantHandler public handler;

    function setUp() public {
        setUpMockAuctionInvariant();

        logFuzzDeploymentParams($deploymentParams);

        address[] memory actors = new address[](1);
        actors[0] = alice;

        handler = new AuctionInvariantHandler(mockAuction, actors);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AuctionInvariantHandler.printMetrics.selector;
        excludeSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
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
    function assertAcceptableDustBalances() internal {
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

            uint256 currencySpent = (bid.amountQ96 / FixedPoint96.Q96) - refundAmount;
            uint256 maxValueAtBidPrice = FixedPointMathLib.fullMulDiv(bid.tokensFilled, bid.maxPrice, FixedPoint96.Q96);

            // Allow small rounding tolerance (up to 1 wei) for edge cases with tiny fills
            // where tokensFilled × maxPrice / Q96 might round to zero
            assertLe(
                currencySpent,
                maxValueAtBidPrice + 1,
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
            emit ITokenCurrencyStorage.CurrencySwept(mockAuction.fundsRecipient(), expectedCurrencyRaised);
            mockAuction.sweepCurrency();
            // Assert that the funds recipient received the currency
            assertEq(
                mockAuction.fundsRecipient().balance,
                expectedCurrencyRaised,
                'Funds recipient balance does not match expected currency raised'
            );
        } else {
            emit log_string('==================== NOT GRADUATED AUCTION ====================');
            vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
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

    function invariant_canSweep_thenExitAndClaimAllBids()
        public
        printMetrics
        givenAuctionIsOver
        givenAuctionIsCheckpointed
    {
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
}
