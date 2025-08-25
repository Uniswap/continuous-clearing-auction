// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';

import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from '../src/libraries/DemandLib.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {Tick} from '../src/TickStorage.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';

contract AuctionInvariantHandler is Test {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

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

        BID_MIN_PRICE = uint256(auction.floorPrice() + auction.tickSpacing());
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
        returns (uint256, uint128)
    {
        uint128 tickNumberPrice = uint128(auction.floorPrice() + tickNumber * auction.tickSpacing());
        uint128 maxPrice = uint128(_bound(tickNumberPrice, BID_MIN_PRICE, BID_MAX_PRICE));
        // Round down to the nearest tick boundary
        maxPrice -= (maxPrice % uint128(auction.tickSpacing()));

        if (exactIn) {
            uint256 inputAmount = amount;
            return (inputAmount, maxPrice);
        } else {
            uint256 inputAmount = amount * maxPrice;
            return (inputAmount, maxPrice);
        }
    }

    /// @notice Return the tick immediately equal to or below the given price
    function getLowerTick(uint256 price) public view returns (uint256) {
        uint256 _price = auction.floorPrice();
        while (_price < price) {
            (_price,) = auction.ticks(_price);
            if (_price == type(uint256).max) {
                return _price;
            }
        }
        return _price;
    }

    /// @notice Roll the block number
    function handleRoll(uint256 seed) public {
        if (seed % 3 == 0) vm.roll(block.number + 1);
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(bool exactIn, uint256 actorIndexSeed, uint128 tickNumber)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        uint256 amount = _bound(tickNumber, 1, auction.totalSupply() * 2);
        (uint256 inputAmount, uint128 maxPrice) = useAmountMaxPrice(exactIn, amount, tickNumber);

        if (currency.isAddressZero()) {
            vm.deal(currentActor, inputAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, inputAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }

        uint256 prevTickPrice = getLowerTick(maxPrice);
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
            } else if (maxPrice <= auction.clearingPrice()) {
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

        handler = new AuctionInvariantHandler(auction, actors);
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
        uint256 previousBlock = 0;

        if (currentBlock == 0) {
            return 0;
        }

        while (currentBlock != 0) {
            (uint256 clearingPrice,,,,,,, uint256 prevBlock) = auction.checkpoints(currentBlock);

            if (clearingPrice <= maxPrice) {
                return previousBlock;
            }

            previousBlock = currentBlock;
            currentBlock = prevBlock;
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

        uint256 clearingPrice = auction.clearingPrice();

        uint256 bidCount = handler.bidCount();
        for (uint256 i = 0; i < bidCount; i++) {
            Bid memory bid = getBid(i);

            // Invalid conditions
            if (bid.exitedBlock != 0) continue;
            if (bid.tokensFilled != 0) continue;

            vm.expectEmit(true, true, true, true);
            emit IAuction.BidExited(i, bid.owner);
            if (bid.maxPrice > clearingPrice) {
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
