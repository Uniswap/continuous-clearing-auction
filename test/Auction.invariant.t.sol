// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';

import {Tick} from '../src/TickStorage.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from '../src/libraries/DemandLib.sol';
import {PriceLib} from '../src/libraries/PriceLib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';

import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MockAuction} from './utils/MockAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {console2} from 'forge-std/console2.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionInvariantHandler is Test {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    Auction public auction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint256 public immutable BID_MAX_PRICE;
    uint256 public immutable BID_MIN_PRICE;
    bool public immutable currencyIsToken0;

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

        if (auction.currencyIsToken0()) {
            BID_MAX_PRICE = uint256(auction.floorPrice() - auction.tickSpacing());
            BID_MIN_PRICE = 1;
        } else {
            BID_MAX_PRICE = type(uint256).max;
            BID_MIN_PRICE = uint256(auction.floorPrice() + auction.tickSpacing());
        }
        currencyIsToken0 = auction.currencyIsToken0();
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
            assertTrue(
                PriceLib.priceAfterOrEqual(checkpoint.clearingPrice, auction.floorPrice(), currencyIsToken0),
                'Checkpoint clearing price is not after floor price'
            );
        }
        // Check that the clearing price is strictly after the previous clearing price
        if (_checkpoint.clearingPrice != 0) {
            assertTrue(
                PriceLib.priceAfterOrEqual(checkpoint.clearingPrice, _checkpoint.clearingPrice, currencyIsToken0),
                'Checkpoint clearing price is not monotonic'
            );
        }
        // Check that the cumulative variables are always increasing
        assertGe(checkpoint.totalCleared, _checkpoint.totalCleared, 'Checkpoint total cleared is not increasing');
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
    function useAmountMaxPrice(bool exactIn, uint256 amount, uint256 tickNumber)
        public
        view
        returns (uint256, uint256)
    {
        tickNumber = _bound(tickNumber, 1, 10);
        uint256 tickNumberPrice;
        if (currencyIsToken0) {
            tickNumberPrice = auction.floorPrice() - (tickNumber - 1) * auction.tickSpacing();
        } else {
            tickNumberPrice = auction.floorPrice() + (tickNumber - 1) * auction.tickSpacing();
        }
        uint256 maxPrice = _bound(tickNumberPrice, BID_MIN_PRICE, BID_MAX_PRICE);

        if (currencyIsToken0) {
            maxPrice += (maxPrice % auction.tickSpacing());
        } else {
            maxPrice -= (maxPrice % auction.tickSpacing());
        }

        uint256 inputAmount;
        if (exactIn) {
            inputAmount = amount;
        } else {
            if (currencyIsToken0) {
                inputAmount = amount.fullMulDivUp(FixedPoint96.Q96, maxPrice);
            } else {
                inputAmount = amount.fullMulDivUp(maxPrice, FixedPoint96.Q96);
            }
        }
        return (inputAmount, maxPrice);
    }

    /// @notice Return the tick immediately equal to or below the given price
    function getBeforeTick(uint256 price) public view returns (uint256) {
        uint256 _price = auction.floorPrice();
        while (PriceLib.priceStrictlyBefore(_price, price, currencyIsToken0)) {
            // Advance to the next tick
            uint256 _lastPrice = _price;
            (_price,) = auction.ticks(_price);
            if (
                currencyIsToken0 && _price == auction.MIN_TICK_PRICE()
                    || !currencyIsToken0 && _price == auction.MAX_TICK_PRICE()
            ) {
                return _lastPrice;
            }
        }
        return _price;
    }

    /// @notice Roll the block number
    function handleRoll(uint256 seed) public {
        if (seed % 3 == 0) vm.roll(block.number + 1);
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(bool exactIn, uint256 actorIndexSeed, uint256 tickNumber)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        uint256 amount = _bound(tickNumber, 1, auction.totalSupply() * 2);
        (uint256 inputAmount, uint256 maxPrice) = useAmountMaxPrice(exactIn, amount, tickNumber);

        if (currency.isAddressZero()) {
            vm.deal(currentActor, inputAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, inputAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }

        uint256 prevTickPrice = getBeforeTick(maxPrice);
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
            } else if (PriceLib.priceBeforeOrEqual(maxPrice, auction.clearingPrice(), currencyIsToken0)) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.InvalidBidPrice.selector));
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

        handler = new AuctionInvariantHandler(MockAuction(address(auction)), actors);
        targetContract(address(handler));
    }

    function getCheckpoint(uint256 blockNumber) public view returns (Checkpoint memory) {
        (
            uint256 clearingPrice,
            uint256 blockCleared,
            uint256 totalCleared,
            uint24 mps,
            uint24 cumulativeMps,
            uint256 cumulativeMpsPerPrice,
            uint256 resolvedDemandAboveClearingPrice,
            uint256 prev
        ) = auction.checkpoints(blockNumber);
        return Checkpoint({
            clearingPrice: clearingPrice,
            blockCleared: blockCleared,
            totalCleared: totalCleared,
            mps: mps,
            cumulativeMps: cumulativeMps,
            cumulativeMpsPerPrice: cumulativeMpsPerPrice,
            resolvedDemandAboveClearingPrice: resolvedDemandAboveClearingPrice,
            prev: prev
        });
    }

    function getBid(uint256 bidId) public view returns (Bid memory) {
        (
            bool exactIn,
            uint64 startBlock,
            uint64 exitedBlock,
            uint256 maxPrice,
            address owner,
            uint256 amount,
            uint256 tokensFilled
        ) = auction.bids(bidId);
        return Bid({
            exactIn: exactIn,
            startBlock: startBlock,
            exitedBlock: exitedBlock,
            maxPrice: maxPrice,
            owner: owner,
            amount: amount,
            tokensFilled: tokensFilled
        });
    }

    function getOutbidCheckpointBlock(uint256 maxPrice) public view returns (uint256) {
        uint256 currentBlock = auction.lastCheckpointedBlock();
        uint256 clearingPrice = getCheckpoint(currentBlock).clearingPrice;
        if (clearingPrice == maxPrice) {
            return currentBlock;
        }

        uint256 previousBlock;

        if (currentBlock == 0) {
            return 0;
        }

        while (currentBlock != 0) {
            (clearingPrice,,,,,,, previousBlock) = auction.checkpoints(currentBlock);
            if (PriceLib.priceBeforeOrEqual(clearingPrice, maxPrice, currencyIsToken0)) {
                return previousBlock;
            }

            previousBlock = currentBlock;
            currentBlock = previousBlock;
        }

        return previousBlock;
    }

    function invariant_canAlwaysCheckpointDuringAuction() public {
        if (block.number > auction.startBlock() && block.number < auction.endBlock()) {
            auction.checkpoint();
        }
    }

    function invariant_canExitAndClaimFullyFilledBids() public {
        // Roll to end of the auction
        vm.roll(auction.endBlock());

        // Checkpoint at the end of the auction so clearing price is up to date
        if (auction.lastCheckpointedBlock() != auction.endBlock()) {
            auction.checkpoint();
        }

        uint256 clearingPrice = auction.clearingPrice();

        uint256 bidCount = handler.bidCount();
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = getBid(i);

            // Invalid conditions
            if (bid.exitedBlock != 0) continue;
            if (bid.tokensFilled != 0) continue;

            vm.expectEmit(true, true, true, true);
            emit IAuction.BidExited(i, bid.owner);
            if (PriceLib.priceStrictlyAfter(bid.maxPrice, clearingPrice, currencyIsToken0)) {
                auction.exitBid(i);
            } else {
                uint256 outbidCheckpointBlock = getOutbidCheckpointBlock(bid.maxPrice);
                auction.exitPartiallyFilledBid(i, outbidCheckpointBlock);
            }

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

            vm.expectEmit(true, true, true, true);
            emit IAuction.TokensClaimed(bid.owner, bid.tokensFilled);
            auction.claimTokens(i);

            bid = getBid(i);
            assertEq(bid.tokensFilled, 0);
        }
    }
}
