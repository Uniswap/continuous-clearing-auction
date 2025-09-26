// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {Tick} from '../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from '../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';

import {MPSLib} from '../src/libraries/MPSLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {Test} from 'forge-std/Test.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionInvariantHandler is Test, Assertions {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    Auction public auction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint256 public constant BID_MAX_PRICE = type(uint256).max;
    uint256 public BID_MIN_PRICE;

    // Ghost variables
    Checkpoint _checkpoint;
    uint256[] public bidIds;
    uint256 public bidCount;

    constructor(Auction _auction, address[] memory _actors) {
        auction = _auction;
        permit2 = IPermit2(auction.PERMIT2());
        currency = auction.currency();
        token = auction.token();
        actors = _actors;

        BID_MIN_PRICE = auction.floorPrice() + auction.tickSpacing();
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[_bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier validateCheckpoint() {
        _;
        Checkpoint memory checkpoint = auction.latestCheckpoint();
        if (checkpoint.clearingPrice != 0) {
            assertGe(checkpoint.clearingPrice, auction.floorPrice());
        }
        // Check that the clearing price is always increasing
        assertGe(checkpoint.clearingPrice, _checkpoint.clearingPrice, 'Checkpoint clearing price is not increasing');
        // Check that the cumulative variables are always increasing
        assertGe(
            checkpoint.totalClearedX7X7, _checkpoint.totalClearedX7X7, 'Checkpoint total cleared is not increasing'
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
    function _useAmountMaxPrice(bool exactIn, uint256 amount, uint256 tickNumber)
        internal
        view
        returns (uint256, uint256)
    {
        tickNumber = _bound(tickNumber, 0, type(uint8).max);
        uint256 tickNumberPrice = auction.floorPrice() + tickNumber * auction.tickSpacing();
        uint256 maxPrice = _bound(tickNumberPrice, BID_MIN_PRICE, BID_MAX_PRICE);
        // Round down to the nearest tick boundary
        maxPrice -= (maxPrice % auction.tickSpacing());

        if (exactIn) {
            uint256 inputAmount = amount;
            return (inputAmount, maxPrice);
        } else {
            uint256 inputAmount = amount.fullMulDivUp(maxPrice, FixedPoint96.Q96);
            return (inputAmount, maxPrice);
        }
    }

    /// @notice Return the tick immediately equal to or below the given price
    function _getLowerTick(uint256 maxPrice) internal view returns (uint256) {
        uint256 _price = auction.floorPrice();
        // If the bid price is less than the floor, we won't be able to find a prev pointer
        // So return 0 here and account for it in the test
        if (maxPrice <= _price) {
            return 0;
        }
        uint256 _cachedPrice = _price;
        while (_price < maxPrice) {
            // Set _price to the next price
            _price = auction.ticks(_price).next;
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

    function handleCheckpoint() public {
        if (block.number > auction.endBlock()) vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.checkpoint();
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(bool exactIn, uint256 actorIndexSeed, uint256 tickNumber)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        // Bid requests for anything between 1 and 2x the total supply of tokens
        uint256 amount = _bound(tickNumber, 1, auction.totalSupply() * 2);
        (uint256 inputAmount, uint256 maxPrice) = _useAmountMaxPrice(exactIn, amount, tickNumber);
        if (currency.isAddressZero()) {
            vm.deal(currentActor, inputAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, inputAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }

        uint256 prevTickPrice = _getLowerTick(maxPrice);
        uint256 nextBidId = auction.nextBidId();
        try auction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, exactIn, exactIn ? inputAmount : amount, currentActor, prevTickPrice, bytes('')
        ) {
            bidIds.push(nextBidId);
            bidCount++;
        } catch (bytes memory revertData) {
            if (block.number >= auction.endBlock()) {
                assertEq(revertData, abi.encodeWithSelector(IAuctionStepStorage.AuctionIsOver.selector));
            } else if (inputAmount == 0) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.InvalidAmount.selector));
            } else if (prevTickPrice == 0) {
                assertEq(revertData, abi.encodeWithSelector(ITickStorage.TickPriceNotIncreasing.selector));
            } else {
                // For race conditions or any errors that require additional calls to be made
                if (bytes4(revertData) == bytes4(abi.encodeWithSelector(IAuction.InvalidBidPrice.selector))) {
                    // See if we checkpoint, that the bid maxPrice would be at an invalid price
                    auction.checkpoint();
                    // Because it reverted from InvalidBidPrice, we must assert that it should have
                    assertLe(maxPrice, auction.clearingPrice());
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

contract AuctionInvariantTest is AuctionBaseTest {
    AuctionInvariantHandler public handler;

    function setUp() public {
        setUpAuction();

        address[] memory actors = new address[](1);
        actors[0] = alice;

        handler = new AuctionInvariantHandler(auction, actors);
        targetContract(address(handler));
    }

    function getCheckpoint(uint64 blockNumber) public view returns (Checkpoint memory) {
        return auction.checkpoints(blockNumber);
    }

    function getBid(uint256 bidId) public view returns (Bid memory) {
        return auction.bids(bidId);
    }

    /// Helper function to return the correct checkpoint hints for a partiallFilledBid
    function getLowerUpperCheckpointHints(uint256 maxPrice) public view returns (uint64 lower, uint64 upper) {
        uint64 currentBlock = auction.lastCheckpointedBlock();

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
        if (block.number >= auction.startBlock() && block.number < auction.endBlock()) {
            auction.checkpoint();
        }
    }

    function invariant_canExitAndClaimFullyFilledBids() public {
        // Roll to end of the auction
        vm.roll(auction.endBlock());
        auction.checkpoint();

        Checkpoint memory finalCheckpoint = getCheckpoint(uint64(block.number));
        // Assert the only thing we know for sure is that the schedule must be 100% at the endBlock
        assertEq(finalCheckpoint.cumulativeMps, MPSLib.MPS, 'Final checkpoint must be 1e7');
        uint256 clearingPrice = auction.clearingPrice();

        uint256 bidCount = handler.bidCount();
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = getBid(i);

            // Invalid conditions
            if (bid.exitedBlock != 0) continue;
            if (bid.tokensFilled != 0) continue;

            uint256 ownerBalanceBefore = address(bid.owner).balance;
            uint256 bidInputAmount =
                bid.exactIn ? bid.amount : BidLib.inputAmount(bid.exactIn, bid.amount, bid.maxPrice);

            if (bid.maxPrice > clearingPrice) {
                auction.exitBid(i);
            } else {
                (uint64 lower, uint64 upper) = getLowerUpperCheckpointHints(bid.maxPrice);
                auction.exitPartiallyFilledBid(i, lower, upper);
            }

            // can never gain more Currency than provided
            assertLe(
                address(bid.owner).balance - ownerBalanceBefore,
                bidInputAmount,
                'Bid owner can never be refunded more Currency than provided'
            );

            // Bid might be deleted if tokensFilled = 0
            bid = getBid(i);
            if (bid.tokensFilled == 0) continue;
            assertEq(bid.exitedBlock, block.number);
        }

        vm.roll(auction.claimBlock());
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = getBid(i);
            if (bid.tokensFilled == 0) continue;
            assertNotEq(bid.exitedBlock, 0);

            uint256 ownerBalanceBefore = token.balanceOf(bid.owner);
            vm.expectEmit(true, true, false, false);
            emit IAuction.TokensClaimed(i, bid.owner, bid.tokensFilled);
            auction.claimTokens(i);
            // Assert that the owner received the tokens
            assertEq(token.balanceOf(bid.owner), ownerBalanceBefore + bid.tokensFilled);

            bid = getBid(i);
            assertEq(bid.tokensFilled, 0);
        }
    }
}
