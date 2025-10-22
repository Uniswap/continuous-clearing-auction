// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {Tick, TickStorage} from '../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint128} from '../src/libraries/FixedPoint128.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionUnitTest} from './unit/AuctionUnitTest.sol';
import {Assertions} from './utils/Assertions.sol';

import {FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {MockAuction} from './utils/MockAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

contract AuctionInvariantHandler is Test, Assertions {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for *;
    using ValueX7Lib for *;

    MockAuction public mockAuction;
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

    struct Metrics {
        uint256 cnt_AuctionIsOverError;
        uint256 cnt_BidAmountTooSmallError;
        uint256 cnt_TickPriceNotIncreasingError;
        uint256 cnt_InvalidBidUnableToClearError;
        uint256 cnt_BidMustBeAboveClearingPriceError;
    }

    Metrics public metrics;

    constructor(MockAuction _auction, address[] memory _actors) {
        mockAuction = _auction;
        permit2 = IPermit2(mockAuction.PERMIT2());
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
        // Check that the clearing price is always increasing
        assertGe(checkpoint.clearingPrice, _checkpoint.clearingPrice, 'Checkpoint clearing price is not increasing');
        // Check that the cumulative variables are always increasing
        assertGe(checkpoint.cumulativeMps, _checkpoint.cumulativeMps, 'Checkpoint cumulative mps is not increasing');
        assertGe(
            checkpoint.cumulativeMpsPerPrice,
            _checkpoint.cumulativeMpsPerPrice,
            'Checkpoint cumulative mps per price is not increasing'
        );

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

    /// @notice Roll the block number
    function handleRoll(uint256 seed) public {
        // TODO(ez): Remove this once we have a better way to fuzz auction duration
        if (seed % 888 == 0) vm.roll(block.number + 1);
    }

    function handleCheckpoint() public validateCheckpoint {
        if (block.number < mockAuction.startBlock()) vm.expectRevert(IAuction.AuctionNotStarted.selector);
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
        try mockAuction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, inputAmount, currentActor, prevTickPrice, bytes('')
        ) {
            bidIds.push(nextBidId);
            bidCount++;
        } catch (bytes memory revertData) {
            if (block.number >= mockAuction.endBlock()) {
                assertEq(revertData, abi.encodeWithSelector(IAuctionStepStorage.AuctionIsOver.selector));
                metrics.cnt_AuctionIsOverError++;
            } else if (inputAmount == 0) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.BidAmountTooSmall.selector));
                metrics.cnt_BidAmountTooSmallError++;
            } else if (
                // If the prevTickPrice is 0, it could maybe be a race that the clearing price has increased since the bid was placed
                // This is handled in the else condition - so we exclude it here
                prevTickPrice == 0
                    && bytes4(revertData)
                        != bytes4(abi.encodeWithSelector(IAuction.BidMustBeAboveClearingPrice.selector))
            ) {
                assertEq(revertData, abi.encodeWithSelector(ITickStorage.TickPriceNotIncreasing.selector));
                metrics.cnt_TickPriceNotIncreasingError++;
            } else if (
                mockAuction.sumCurrencyDemandAboveClearingQ96()
                    >= ConstantsLib.X7_UPPER_BOUND - (inputAmount * FixedPoint96.Q96 * ConstantsLib.MPS)
                        / (ConstantsLib.MPS - _checkpoint.cumulativeMps)
            ) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.InvalidBidUnableToClear.selector));
                metrics.cnt_InvalidBidUnableToClearError++;
            } else {
                // For race conditions or any errors that require additional calls to be made
                if (bytes4(revertData) == bytes4(abi.encodeWithSelector(IAuction.BidMustBeAboveClearingPrice.selector)))
                {
                    // See if we checkpoint, that the bid maxPrice would be at an invalid price
                    mockAuction.checkpoint();
                    // Because it reverted from BidMustBeAboveClearingPrice, we must assert that it should have
                    assertLe(maxPrice, mockAuction.clearingPrice());
                    metrics.cnt_BidMustBeAboveClearingPriceError++;
                } else {
                    // Uncaught error so we bubble up the revert reason
                    emit log_string('Invariant::handleSubmitBid: Uncaught error');
                    assembly {
                        revert(add(revertData, 0x20), mload(revertData))
                    }
                }
            }
        }
    }

    function printMetrics() public {
        emit log_string('==================== METRICS ====================');
        emit log_named_uint('bidCount', bidCount);
        emit log_named_uint('AuctionIsOverError count', metrics.cnt_AuctionIsOverError);
        emit log_named_uint('BidAmountTooSmallError count', metrics.cnt_BidAmountTooSmallError);
        emit log_named_uint('TickPriceNotIncreasingError count', metrics.cnt_TickPriceNotIncreasingError);
        emit log_named_uint('InvalidBidUnableToClearError count', metrics.cnt_InvalidBidUnableToClearError);
        emit log_named_uint('BidMustBeAboveClearingPriceError count', metrics.cnt_BidMustBeAboveClearingPriceError);
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
        _;
        handler.printMetrics();
    }

    function getCheckpoint(uint64 blockNumber) public view returns (Checkpoint memory) {
        return mockAuction.checkpoints(blockNumber);
    }

    function getBid(uint256 bidId) public view returns (Bid memory) {
        return mockAuction.bids(bidId);
    }

    /// Helper function to return the correct checkpoint hints for a partiallFilledBid
    function getLowerUpperCheckpointHints(uint256 maxPrice) public view returns (uint64 lower, uint64 upper) {
        uint64 currentBlock = mockAuction.lastCheckpointedBlock();

        // Traverse checkpoints from most recent to oldest
        while (currentBlock != 0) {
            Checkpoint memory checkpoint = getCheckpoint(currentBlock);

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

    function invariant_canAlwaysCheckpointDuringAuction() public printMetrics {
        if (block.number >= mockAuction.startBlock() && block.number < mockAuction.claimBlock()) {
            mockAuction.checkpoint();
        }
    }

    function invariant_canExitAndClaimAllBids() public printMetrics {
        // Roll to end of the auction
        vm.roll(mockAuction.endBlock());
        mockAuction.checkpoint();

        Checkpoint memory finalCheckpoint = getCheckpoint(uint64(block.number));
        // Assert the only thing we know for sure is that the schedule must be 100% at the endBlock
        assertEq(finalCheckpoint.cumulativeMps, ConstantsLib.MPS, 'Final checkpoint must be 1e7');
        uint256 clearingPrice = mockAuction.clearingPrice();

        uint256 bidCount = handler.bidCount();
        uint256 totalCurrencyRaised;
        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = handler.bidIds(i);
            Bid memory bid = getBid(bidId);

            uint256 ownerBalanceBefore = address(bid.owner).balance;

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
            assertLe(refundAmount, bid.amountQ96, 'Bid owner can never be refunded more Currency than provided');

            // Bid might be deleted if tokensFilled = 0
            bid = getBid(bidId);
            if (bid.tokensFilled == 0) continue;
            assertEq(bid.exitedBlock, block.number);
        }

        vm.roll(mockAuction.claimBlock());
        for (uint256 i = 0; i < bidCount; i++) {
            uint256 bidId = handler.bidIds(i);
            Bid memory bid = getBid(bidId);
            if (bid.tokensFilled == 0) continue;
            assertNotEq(bid.exitedBlock, 0);

            uint256 ownerBalanceBefore = token.balanceOf(bid.owner);
            vm.expectEmit(true, true, false, false);
            emit IAuction.TokensClaimed(bidId, bid.owner, bid.tokensFilled);
            mockAuction.claimTokens(bidId);
            // Assert that the owner received the tokens
            assertEq(token.balanceOf(bid.owner), ownerBalanceBefore + bid.tokensFilled);

            bid = getBid(bidId);
            assertEq(bid.tokensFilled, 0);
        }

        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();

        emit log_string('==================== AFTER EXIT AND CLAIM TOKENS ====================');
        emit log_named_uint('bidCount', bidCount);
        emit log_named_uint('auction duration (blocks)', mockAuction.endBlock() - mockAuction.startBlock());
        emit log_named_decimal_uint('auction currency balance', address(mockAuction).balance, 18);
        emit log_named_decimal_uint('actualCurrencyRaised (from all bids after refunds)', totalCurrencyRaised, 18);
        emit log_named_decimal_uint('expectedCurrencyRaised (for sweepCurrency())', expectedCurrencyRaised, 18);

        assertEq(
            address(mockAuction).balance,
            totalCurrencyRaised,
            'Auction currency balance does not match total currency raised'
        );

        mockAuction.sweepUnsoldTokens();
        if (mockAuction.isGraduated()) {
            assertLe(
                expectedCurrencyRaised,
                address(mockAuction).balance,
                'Expected currency raised is greater than auction balance'
            );
            // Sweep the currency
            vm.expectEmit(true, true, true, true);
            emit ITokenCurrencyStorage.CurrencySwept(mockAuction.fundsRecipient(), expectedCurrencyRaised);
            mockAuction.sweepCurrency();
            // Assert that the currency was swept and matches total currency raised
            assertLe(
                expectedCurrencyRaised,
                totalCurrencyRaised,
                'Expected currency raised is greater than total currency raised'
            );
            // Assert that the funds recipient received the currency
            assertEq(
                mockAuction.fundsRecipient().balance,
                expectedCurrencyRaised,
                'Funds recipient balance does not match expected currency raised'
            );
            assertApproxEqAbs(address(mockAuction).balance, 0, 1e6, 'Auction balance is not within 1e6 wei of zero');
        } else {
            vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
            mockAuction.sweepCurrency();
            // At this point we know all bids have been exited so auction balance should be zero
            assertEq(address(mockAuction).balance, 0, 'Auction balance is not zero after sweeping currency');
        }
    }
}
