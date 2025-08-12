// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';

import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {Test} from 'forge-std/Test.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';

contract AuctionInvariantHandler is Test {
    using CurrencyLibrary for Currency;

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

    function handleSubmitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        uint128 prevHintId,
        bytes calldata hookData,
        uint256 actorIndexSeed
    ) public payable useActor(actorIndexSeed) returns (uint256) {
        if (currency.isAddressZero()) {
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }
        return auction.submitBid{value: msg.value}(maxPrice, exactIn, amount, currentActor, prevHintId, hookData);
    }
}

contract AuctionInvariantTest is AuctionBaseTest {
    AuctionInvariantHandler public handler;

    function setUp() public {
        setUpAuction();

        address[] memory actors = new address[](1);
        actors[0] = alice;

        handler = new AuctionInvariantHandler(auction, actors);
    }
}
