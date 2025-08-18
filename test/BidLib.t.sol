// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Bid} from '../src/libraries/BidLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MockBidLib} from './utils/MockBidLib.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract BidLibTest is Test {
    MockBidLib mockBidLib;

    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    uint24 public constant MPS = 1e7;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant ETH_AMOUNT = 10 ether;
    uint128 public constant MAX_PRICE = 5000;
    uint256 public constant TOKEN_AMOUNT = 1000;

    function setUp() public {
        mockBidLib = new MockBidLib();
    }

    function test_resolve_exactOut_calculatePartialFill_succeeds() public view {
        // Buy exactly 1000 tokens at max price 2000 per token
        uint256 exactOutAmount = 1000e18;
        uint256 totalEth = 2000 * exactOutAmount;
        uint256 maxPrice = 2000;
        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: exactOutAmount,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: maxPrice
        });

        // Execute: 30% of auction executed (3000 mps)
        uint24 cumulativeMpsDelta = 3000e3;
        uint256 cumulativeMpsPerPriceDelta = uint256(cumulativeMpsDelta << FixedPoint96.RESOLUTION) / maxPrice;

        uint256 tokensFilled = mockBidLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);
        uint256 refund = mockBidLib.calculateRefund(bid, maxPrice, tokensFilled, cumulativeMpsDelta, MPS);

        // 30% of 1000e18 tokens = 300e18 tokens filled
        assertEq(tokensFilled, 300e18);
        assertEq(refund, totalEth - totalEth * cumulativeMpsDelta / MPS);
    }

    function test_resolve_exactIn_fuzz_succeeds(uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        public
        view
    {
        vm.assume(cumulativeMpsDelta <= MPS);
        // Setup: User commits 10 ETH to buy tokens
        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 tokensFilled = mockBidLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);
        mockBidLib.calculateRefund(bid, MAX_PRICE, tokensFilled, cumulativeMpsDelta, MPS);
    }

    function test_resolve_exactOut_fuzz_succeeds(uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        public
        view
    {
        vm.assume(cumulativeMpsDelta <= MPS);
        // Setup: User commits to buy 1000 tokens at max price 2000 per token
        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 maxPrice = 2000;
        uint256 _expectedTokensFilled = TOKEN_AMOUNT.applyMps(cumulativeMpsDelta);

        uint256 tokensFilled = mockBidLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);
        uint256 refund = mockBidLib.calculateRefund(bid, maxPrice, tokensFilled, cumulativeMpsDelta, MPS);

        assertEq(tokensFilled, _expectedTokensFilled);
        assertEq(refund, maxPrice * (TOKEN_AMOUNT - _expectedTokensFilled));
    }

    function test_resolve_exactIn() public view {
        uint24[] memory mpsArray = new uint24[](3);
        uint256[] memory pricesArray = new uint256[](3);

        mpsArray[0] = 50e3;
        pricesArray[0] = 100;

        mpsArray[1] = 30e3;
        pricesArray[1] = 200;

        mpsArray[2] = 20e3;
        pricesArray[2] = 200;

        uint256 _tokensFilled;
        uint256 _ethSpent;
        uint256 _totalMps;
        uint256 _cumulativeMpsPerPrice;

        for (uint256 i = 0; i < 3; i++) {
            uint256 ethSpentInBlock = ETH_AMOUNT * mpsArray[i] / MPS;
            uint256 tokensFilledInBlock = ethSpentInBlock / pricesArray[i];
            _tokensFilled += tokensFilledInBlock;
            _ethSpent += ethSpentInBlock;

            _totalMps += mpsArray[i];
            // uint24.max << 96 will not overflow
            _cumulativeMpsPerPrice += uint256(mpsArray[i] << FixedPoint96.RESOLUTION) / pricesArray[i];
        }

        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // 50e3 * 1e18 / 100 = 0.5 * 1e18
        // 30e3 * 1e18 / 200 = 0.15 * 1e18
        // 20e3 * 1e18 / 200 = 0.1 * 1e18
        // 0.5 + 0.15 + 0.1 = 0.75 * 1e18 * 1e3 (for mps)
        assertEq(_cumulativeMpsPerPrice, 0.75 ether * 1e3);
        uint256 tokensFilled = mockBidLib.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps), MPS);
        uint256 refund = mockBidLib.calculateRefund(bid, MAX_PRICE, tokensFilled, uint24(_totalMps), MPS);

        // Manual tokensFilled calculation:
        // 10 * 1e18 * 0.75 * 1e18 / 1e18 * 1e4 = 7.5 * 1e18 / 1e4 = 7.5e14
        assertEq(tokensFilled, 7.5e14);
        // Manual refund calculation:
        assertEq(refund, ETH_AMOUNT - _ethSpent);
    }

    function test_resolve_exactOut() public view {
        uint256[] memory mpsArray = new uint256[](3);
        uint256[] memory pricesArray = new uint256[](3);

        mpsArray[0] = 50;
        pricesArray[0] = 100;

        mpsArray[1] = 30;
        pricesArray[1] = 200;

        mpsArray[2] = 20;
        pricesArray[2] = MAX_PRICE;

        uint256 _totalMps;

        for (uint256 i = 0; i < 3; i++) {
            _totalMps += mpsArray[i];
        }

        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // Bid is fully filled since max price is always higher than all prices
        uint256 tokensFilled = mockBidLib.calculateFill(bid, 0, uint24(_totalMps), MPS);
        uint256 refund = mockBidLib.calculateRefund(bid, MAX_PRICE, tokensFilled, uint24(_totalMps), MPS);

        assertEq(tokensFilled, TOKEN_AMOUNT.applyMps(uint24(_totalMps)));
        assertEq(refund, MAX_PRICE * (TOKEN_AMOUNT - tokensFilled));
    }

    function test_resolve_exactIn_maxPrice() public view {
        uint24[] memory mpsArray = new uint24[](1);
        uint256[] memory pricesArray = new uint256[](1);

        mpsArray[0] = MPS;
        pricesArray[0] = MAX_PRICE;

        // Setup: Large ETH bid
        uint256 largeAmount = 100 ether;
        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: largeAmount,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // uint24.max << 96 will not overflow
        uint256 cumulativeMpsPerPriceDelta = uint256(mpsArray[0] << FixedPoint96.RESOLUTION) / pricesArray[0];
        uint24 cumulativeMpsDelta = MPS;
        uint256 ethSpent = largeAmount * cumulativeMpsDelta / MPS;

        assertEq(ethSpent, largeAmount);

        uint256 expectedTokensFilled = ethSpent / MAX_PRICE;

        uint256 tokensFilled = mockBidLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);
        uint256 refund = mockBidLib.calculateRefund(bid, MAX_PRICE, tokensFilled, cumulativeMpsDelta, MPS);

        assertEq(tokensFilled, expectedTokensFilled);
        assertEq(refund, 0);
    }
}
