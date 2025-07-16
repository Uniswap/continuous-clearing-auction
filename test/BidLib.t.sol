// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Bid} from '../src/libraries/BidLib.sol';
import {MockBidLib} from './utils/MockBidLib.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract BidLibTest is Test {
    MockBidLib mockBidLib;

    using FixedPointMathLib for uint256;

    uint256 public constant BPS = 10_000;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ETH_AMOUNT = 10 ether;
    uint128 public constant MAX_PRICE = 5000;
    uint256 public constant TOKEN_AMOUNT = 1000;

    function setUp() public {
        mockBidLib = new MockBidLib();
    }

    function test_resolve_exactOut_partialFill_succeeds() public view {
        // Buy exactly 1000 tokens at max price 2000 per token
        uint256 exactOutAmount = 1000e18;
        uint256 totalEth = 2000 * exactOutAmount;
        Bid memory bid = Bid({
            exactIn: false,
            maxPrice: 2000,
            owner: address(this),
            amount: exactOutAmount,
            tokensFilled: 0,
            startBlock: 100,
            withdrawnBlock: 0
        });

        // Execute: 30% of auction executed (3000 bps)
        uint16 cumulativeBpsDelta = 3000;
        uint256 cumulativeBpsPerPriceDelta = uint256(cumulativeBpsDelta).fullMulDiv(PRECISION, 2000);

        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);

        // 30% of 1000e18 tokens = 300e18 tokens filled
        assertEq(tokensFilled, 300e18);
        assertEq(refund, totalEth - totalEth * cumulativeBpsDelta / BPS);
    }

    function test_resolve_exactIn_fuzz_succeeds(uint256 cumulativeBpsPerPriceDelta, uint16 cumulativeBpsDelta)
        public
        view
    {
        vm.assume(cumulativeBpsDelta <= BPS);
        // Setup: User commits 10 ETH to buy tokens
        Bid memory bid = Bid({
            exactIn: true,
            maxPrice: MAX_PRICE,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            withdrawnBlock: 0
        });

        mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);
    }

    function test_resolve_exactIn() public view {
        uint256[] memory bpsArray = new uint256[](3);
        uint256[] memory pricesArray = new uint256[](3);

        bpsArray[0] = 50;
        pricesArray[0] = 100;

        bpsArray[1] = 30;
        pricesArray[1] = 200;

        bpsArray[2] = 20;
        pricesArray[2] = 200;

        uint256 _tokensFilled;
        uint256 _ethSpent;
        uint256 _totalBps;
        uint256 _cumulativeBpsPerPrice;

        for (uint256 i = 0; i < 3; i++) {
            uint256 ethSpentInBlock = ETH_AMOUNT * bpsArray[i] / BPS;
            uint256 tokensFilledInBlock = ethSpentInBlock / pricesArray[i];
            _tokensFilled += tokensFilledInBlock;
            _ethSpent += ethSpentInBlock;

            _totalBps += bpsArray[i];
            _cumulativeBpsPerPrice += uint256(bpsArray[i]).fullMulDiv(PRECISION, pricesArray[i]);
        }

        Bid memory bid = Bid({
            exactIn: true,
            maxPrice: MAX_PRICE,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            withdrawnBlock: 0
        });

        // 50 * 1e18 / 100 = 0.5 * 1e18
        // 30 * 1e18 / 200 = 0.15 * 1e18
        // 20 * 1e18 / 200 = 0.1 * 1e18
        // 0.5 + 0.15 + 0.1 = 0.75 * 1e18
        assertEq(_cumulativeBpsPerPrice, 0.75 ether);
        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, _cumulativeBpsPerPrice, uint16(_totalBps));

        // Manual tokensFilled calculation:
        // 10 * 1e18 * 0.75 * 1e18 / 1e18 * 1e4 = 7.5 * 1e18 / 1e4 = 7.5e14
        assertEq(tokensFilled, 7.5e14);
        // Manual refund calculation:
        assertEq(refund, ETH_AMOUNT - _ethSpent);
    }

    function test_resolve_exactIn_maxPrice() public view {
        uint16[] memory bpsArray = new uint16[](1);
        uint256[] memory pricesArray = new uint256[](1);

        bpsArray[0] = 10_000;
        pricesArray[0] = MAX_PRICE;

        // Setup: Large ETH bid
        uint256 largeAmount = 100 ether;
        Bid memory bid = Bid({
            exactIn: true,
            maxPrice: MAX_PRICE,
            owner: address(this),
            amount: largeAmount,
            tokensFilled: 0,
            startBlock: 100,
            withdrawnBlock: 0
        });

        uint256 cumulativeBpsPerPriceDelta = uint256(bpsArray[0]).fullMulDiv(PRECISION, pricesArray[0]);
        uint16 cumulativeBpsDelta = 10_000;
        uint256 ethSpent = largeAmount * cumulativeBpsDelta / BPS;

        assertEq(ethSpent, largeAmount);

        uint256 expectedTokensFilled = ethSpent / MAX_PRICE;

        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);

        assertEq(tokensFilled, expectedTokensFilled);
        assertEq(refund, 0);
    }
}
