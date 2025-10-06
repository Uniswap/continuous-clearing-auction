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
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';

import {AuctionUnitTest} from './unit/AuctionUnitTest.sol';
import {Assertions} from './utils/Assertions.sol';
import {MockAuction} from './utils/MockAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionInvariantHandler is Test, Assertions {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    MockAuction public mockAuction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint256 public constant BID_MAX_PRICE = BidLib.MAX_BID_PRICE;
    uint256 public BID_MIN_PRICE;

    // Ghost variables
    Checkpoint _checkpoint;
    uint256[] public bidIds;
    uint256 public bidCount;

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
        // If the clearing price is higher than the floor price, ensure that the supplyMultiplier is set
        if (checkpoint.clearingPrice > mockAuction.floorPrice()) {
            (bool isSet, uint24 remainingMps, ValueX7X7 remainingCurrencyRaisedX7X7) =
                mockAuction.unpackSupplyRolloverMultiplier();
            assertEq(isSet, true, 'Supply rollover multiplier is not set when clearing price is above floor price');
            assertLe(remainingMps, ConstantsLib.MPS, 'Remaining mps is greater than ConstantsLib.MPS');
            assertLe(
                remainingCurrencyRaisedX7X7,
                mockAuction.getTotalCurrencyRaisedAtFloorX7X7(),
                'Remaining currency raised is greater than total currency raised at floor'
            );
        }
        // Check that the cumulative variables are always increasing
        assertGe(
            checkpoint.totalCurrencyRaisedX7X7,
            _checkpoint.totalCurrencyRaisedX7X7,
            'Checkpoint total currency raised is not increasing'
        );
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
    function _useAmountMaxPrice(uint256 amount, uint8 tickNumber) internal view returns (uint256, uint256) {
        uint256 tickNumberPrice = mockAuction.floorPrice() + tickNumber * mockAuction.tickSpacing();
        uint256 maxPrice = _bound(tickNumberPrice, BID_MIN_PRICE, BID_MAX_PRICE);
        // Round down to the nearest tick boundary
        maxPrice -= (maxPrice % mockAuction.tickSpacing());

        uint256 inputAmount = amount.fullMulDivUp(maxPrice, FixedPoint96.Q96);
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
        if (seed % 3 == 0) vm.roll(block.number + 1);
    }

    function handleCheckpoint() public validateCheckpoint {
        if (block.number > mockAuction.endBlock()) vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        mockAuction.checkpoint();
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(uint256 actorIndexSeed, uint256 bidAmount, uint8 tickNumber)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        // Bid requests for anything between 1 and 2x the total supply of tokens
        uint256 amount = _bound(bidAmount, BidLib.MIN_BID_AMOUNT, mockAuction.totalSupply() * 2);
        (uint256 inputAmount, uint256 maxPrice) = _useAmountMaxPrice(amount, tickNumber);
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
        console.log('submitting bid with', inputAmount, maxPrice, prevTickPrice);
        try mockAuction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, inputAmount, currentActor, prevTickPrice, bytes('')
        ) {
            bidIds.push(nextBidId);
            bidCount++;
        } catch (bytes memory revertData) {
            if (block.number >= mockAuction.endBlock()) {
                assertEq(revertData, abi.encodeWithSelector(IAuctionStepStorage.AuctionIsOver.selector));
            } else if (inputAmount == 0) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.BidAmountTooSmall.selector));
            } else if (prevTickPrice == 0) {
                assertEq(revertData, abi.encodeWithSelector(ITickStorage.TickPriceNotIncreasing.selector));
            } else {
                // For race conditions or any errors that require additional calls to be made
                if (bytes4(revertData) == bytes4(abi.encodeWithSelector(IAuction.InvalidBidPrice.selector))) {
                    // See if we checkpoint, that the bid maxPrice would be at an invalid price
                    mockAuction.checkpoint();
                    // Because it reverted from InvalidBidPrice, we must assert that it should have
                    assertLe(maxPrice, mockAuction.clearingPrice());
                } else {
                    // Uncaught error so we bubble up the revert reason
                    assembly {
                        revert(add(revertData, 0x20), mload(revertData))
                    }
                }
            }
        }
    }
}

contract AuctionInvariantTest is AuctionUnitTest {
    AuctionInvariantHandler public handler;

    function setUp() public {
        setUpMockAuction();

        address[] memory actors = new address[](1);
        actors[0] = alice;

        handler = new AuctionInvariantHandler(mockAuction, actors);
        targetContract(address(handler));
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

    function invariant_canAlwaysCheckpointDuringAuction() public {
        if (block.number >= mockAuction.startBlock() && block.number < mockAuction.endBlock()) {
            mockAuction.checkpoint();
        }
    }

    function invariant_canExitAndClaimAllBids() public {
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
            console.log('refundAmount', refundAmount);
            console.log('bid.amount', bid.amount);
            totalCurrencyRaised += bid.amount - refundAmount;

            // can never gain more Currency than provided
            assertLe(refundAmount, bid.amount, 'Bid owner can never be refunded more Currency than provided');

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
        emit log_named_decimal_uint('auction balance', address(mockAuction).balance, 18);
        emit log_named_decimal_uint('totalCurrencyRaised', totalCurrencyRaised, 18);
        emit log_named_decimal_uint('expectedCurrencyRaised', expectedCurrencyRaised, 18);

        assertEq(
            expectedCurrencyRaised,
            address(mockAuction).balance,
            'Expected currency raised is greater than auction balance'
        );

        mockAuction.sweepUnsoldTokens();
        if (mockAuction.isGraduated()) {
            // Sweep the currency
            vm.expectEmit(true, true, true, true);
            emit ITokenCurrencyStorage.CurrencySwept(mockAuction.fundsRecipient(), expectedCurrencyRaised);
            mockAuction.sweepCurrency();
            // Assert that the currency was swept and matches total currency raised
            assertEq(
                expectedCurrencyRaised,
                totalCurrencyRaised,
                'Expected currency raised does not match total currency raised'
            );
            // Assert that the funds recipient received the currency
            assertEq(
                mockAuction.fundsRecipient().balance,
                expectedCurrencyRaised,
                'Funds recipient balance does not match expected currency raised'
            );
        } else {
            vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
            mockAuction.sweepCurrency();
            // At this point we know all bids have been exited so auction balance should be zero
            assertEq(address(mockAuction).balance, 0, 'Auction balance is not zero after sweeping currency');
        }
    }
}
