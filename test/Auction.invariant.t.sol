// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';

import {Tick} from '../src/libraries/TickLib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {console2} from 'forge-std/console2.sol';
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

    constructor(Auction _auction, address[] memory _actors) {
        auction = _auction;
        permit2 = IPermit2(auction.PERMIT2());
        currency = auction.currency();
        token = auction.token();
        actors = _actors;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function useMaxPrice(uint128 seed) public view returns (uint128) {
        uint128 maxPrice = uint128(bound(seed, auction.floorPrice(), type(uint128).max));
        // Round down to the nearest tick boundary
        return maxPrice - (maxPrice % uint128(auction.tickSpacing()));
    }

    function handleSubmitBid(bool exactIn, uint256 amount, uint256 actorIndexSeed, uint128 maxPriceSeed)
        public
        payable
        useActor(actorIndexSeed)
        returns (uint256)
    {
        uint128 maxPrice = useMaxPrice(maxPriceSeed);
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, auction.tickSpacing());

        if (currency.isAddressZero()) {
            vm.deal(currentActor, resolvedAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, resolvedAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }

        Tick memory upper = auction.getLowerTickForPrice(maxPrice);
        // getLowerTickForPrice will return the highest tick in the book so we will use that if returned
        uint128 prevHintId = upper.id == (auction.nextTickId() - 1) ? upper.id : upper.prev;

        if (resolvedAmount == 0) vm.expectRevert(IAuction.InvalidAmount.selector);
        return auction.submitBid{value: currency.isAddressZero() ? resolvedAmount : 0}(
            maxPrice, true, resolvedAmount, currentActor, prevHintId, bytes('')
        );
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

    function invariant_canAlwaysCheckpointDuringAuction() public {
        if (block.number > auction.startBlock() && block.number < auction.endBlock()) {
            auction.checkpoint();
        }
    }
}
