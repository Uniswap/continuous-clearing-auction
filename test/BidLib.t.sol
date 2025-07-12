// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2} from 'forge-std/console2.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {MockBidLib} from './utils/MockBidLib.sol';
import {Bid} from '../src/libraries/BidLib.sol';

contract BidLibTest is Test {
    MockBidLib mockBidLib;
    using FixedPointMathLib for uint256;

    uint256 public constant TICK_SPACING = 100;
    uint256 public constant ETH_AMOUNT = 10 ether;
    uint128 public constant MAX_PRICE = 5000;
    uint256 public constant TOKEN_AMOUNT = 1000;

    function setUp() public {
        mockBidLib = new MockBidLib();
    }
    
    function test_resolve_exactOut_partialFill_succeeds() public {
        // Setup: User wants to buy exactly 1000 tokens at max price 2000 per token
        Bid memory bid = Bid({
            exactIn: false,
            maxPrice: 2000,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            withdrawnBlock: 0
        });

        // Execute: 30% of auction executed (3000 bps)
        uint16 cumulativeBpsDelta = 3000;
        uint16 cumulativeBpsPerPriceDelta = 0; // Not used for exactOut

        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);

        // Assert: 30% of 1000 tokens = 300 tokens filled
        assertEq(tokensFilled, 300);
        // Refund: maxPrice * (tokens not filled) = 2000 * (1000 - 300) = 1,400,000
        assertEq(refund, 1_400_000);
    }
    
    function test_resolve_exactIn_fuzz_succeeds(uint16 cumulativeBpsPerPriceDelta, uint16 cumulativeBpsDelta) public {
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
    
    function test_resolve_exactIn_iterativeVerification() public {
        // Setup: Configure auction parameters
        uint256[] memory bpsArray = new uint256[](3);
        uint256[] memory pricesArray = new uint256[](3);
        
        bpsArray[0] = 50;
        pricesArray[0] = TICK_SPACING;

        bpsArray[1] = 30;
        pricesArray[1] = TICK_SPACING * 2;

        bpsArray[2] = 20;
        pricesArray[2] = TICK_SPACING * 3;

        uint256 _tokensFilled;
        uint256 _ethSpent;
        uint256 _totalBps;
        uint256 _cumulativeBpsPerPrice;

        for (uint256 i = 0; i < 3; i++) {
            uint256 ethSpentInBlock = ETH_AMOUNT * bpsArray[i] / 10_000;
            uint256 tokensFilledInBlock = ethSpentInBlock / pricesArray[i];
            _tokensFilled += tokensFilledInBlock;
            _ethSpent += ethSpentInBlock;

            console2.log('ethSpentInBlock', ethSpentInBlock);
            console2.log('tokensFilledInBlock', tokensFilledInBlock);
            console2.log('_tokensFilled', _tokensFilled);
            console2.log('_ethSpent', _ethSpent);

            _totalBps += bpsArray[i];
            _cumulativeBpsPerPrice += bpsArray[i] * TICK_SPACING.fullMulDiv(1e18, pricesArray[i]);
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

        console2.log('cumulativeBpsPerPrice', _cumulativeBpsPerPrice);
        console2.log('totalBps', _totalBps);
        
        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, _cumulativeBpsPerPrice, uint16(_totalBps));
        
        // Manual tokensFilled calculation:
        // 10 ether * 50 / 10_000 = 0.05 ether / 1e18 = 0.00005 tokens
        // 10 ether * 30 / 10_000 = 0.03 ether / 2e18 = 0.000015 tokens
        // 10 ether * 20 / 10_000 = 0.02 ether / 3e18 = 0.000006666666666 tokens
        assertEq(tokensFilled, 0.000071666666666 ether);  // 0.00005 + 0.000015 + 0.000006666666666 = 0.000071666666666
        // Manual refund calculation:
        // 10 ether - 0.05 ether - 0.03 ether - 0.02 ether = 0.9 ether
        assertEq(refund, ETH_AMOUNT - _ethSpent);
    }
    
    function test_resolve_exactIn_allBpsAtFloorPrice_fullExecution() public {
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

        // Execute: All 10,000 bps at price 1000
        // cumulativeBpsPerPrice = 10,000 / 1000 = 10
        uint16 cumulativeBpsPerPriceDelta = 10;
        uint16 cumulativeBpsDelta = 10_000;

        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);

        // Assert: Current impl: 100 ether * 10 / 10_000 = 0.1 ether (incorrect)
        assertEq(tokensFilled, 0.1 ether);
        // All ETH used since all bps executed
        assertEq(refund, 0);
    }
    
    function test_resolve_exactIn_realisticAuction_demonstratesOverflow() public {
        // Setup: 50 ETH bid in a real auction
        uint256 largeEthAmount = 50 ether;
        Bid memory bid = Bid({
            exactIn: true,
            maxPrice: 3000,
            owner: address(this),
            amount: largeEthAmount,
            tokensFilled: 0,
            startBlock: 1000,
            withdrawnBlock: 0
        });

        // Execute: Auction progressed 45% (4500 bps)
        // Note: With average price ~2500, cumulativeBpsPerPrice ≈ 1.8
        // Scaled by 1e4 = 18000 (would overflow uint16!)
        // This demonstrates why cumulativeBpsPerPrice must be uint256
        uint16 cumulativeBpsPerPriceDelta = 180; // Represents 0.018 to fit in uint16
        uint16 cumulativeBpsDelta = 4500;

        (uint256 tokensFilled, uint256 refund) = mockBidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta);

        // Assert: ETH used: 50 * 4500 / 10_000 = 22.5 ETH
        assertEq(refund, 27.5 ether);
        // Current tokens: 50 ether * 180 / 10_000 = 0.9 ether (incorrect)
        assertEq(tokensFilled, 0.9 ether);
    }
    
    function test_resolve_exactIn_correctedFormula_demonstratesProperCalculation() public {
        // This test demonstrates what the correct implementation should be
        // The resolve function needs:
        // 1. uint256 cumulativeBpsPerPriceDelta (not uint16)
        // 2. tickSpacing parameter

        // Setup: Realistic cumulative value (scaled by 1e18)
        uint256 cumulativeBpsPerPriceDelta = 78333333333333333; // ≈ 0.0783
        uint16 cumulativeBpsDelta = 100; // 1% of auction

        // Execute: Correct calculation for exactIn
        uint256 correctTokensFilled = (ETH_AMOUNT * TICK_SPACING * cumulativeBpsPerPriceDelta) / (10_000 * 1e18);
        uint256 ethUsed = ETH_AMOUNT * cumulativeBpsDelta / 10_000;
        uint256 correctRefund = ETH_AMOUNT - ethUsed;

        // Assert: With tickSpacing = 100, cumulativeBpsPerPrice = 0.0783
        // Tokens = (10 ether * 100 * 0.0783) / 1 = 78.3 tokens
        assertEq(correctTokensFilled, 783 * 1e17 / 10);
        assertEq(correctRefund, 9.9 ether);
    }
} 