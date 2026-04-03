// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionParameters, ContinuousClearingAuction} from '../src/ContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {LBPInitializationParams} from '../src/interfaces/external/ILBPInitializer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title CustodyTokensTest
/// @notice Tests for the custody tokens feature
contract CustodyTokensTest is AuctionBaseTest {
    using FixedPointMathLib for *;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;

    uint128 constant CUSTODY_AMOUNT = 50e18;

    ContinuousClearingAuction custodyAuction;
    AuctionParameters custodyParams;

    function setUp() public {
        setUpTokens();
        alice = makeAddr('alice');
        bob = makeAddr('bob');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        auctionStepsData =
            AuctionStepsBuilder.init().addStep(STANDARD_MPS_1_PERCENT, 50).addStep(STANDARD_MPS_1_PERCENT, 50);

        custodyParams = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE)
            .withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION + CLAIM_BLOCK_OFFSET).withAuctionStepsData(auctionStepsData);
        custodyParams.custodyTokens = CUSTODY_AMOUNT;

        custodyAuction = new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
    }

    // ============================================
    // Getter
    // ============================================

    function test_custodyTokens_getter() public view {
        assertEq(custodyAuction.custodyTokens(), CUSTODY_AMOUNT);
    }

    function test_custodyTokens_zero_getter() public {
        custodyParams.custodyTokens = 0;
        ContinuousClearingAuction zeroAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
        assertEq(zeroAuction.custodyTokens(), 0);
    }

    // ============================================
    // onTokensReceived
    // ============================================

    function test_onTokensReceived_withOnlyTotalSupply_reverts() public {
        // Mint only TOTAL_SUPPLY — should revert because CUSTODY_TOKENS > 0
        token.mint(address(custodyAuction), TOTAL_SUPPLY);
        vm.expectRevert(IContinuousClearingAuction.InvalidTokenAmountReceived.selector);
        custodyAuction.onTokensReceived();
    }

    function test_onTokensReceived_withTotalSupplyPlusCustodyMinusOne_reverts() public {
        token.mint(address(custodyAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT) - 1);
        vm.expectRevert(IContinuousClearingAuction.InvalidTokenAmountReceived.selector);
        custodyAuction.onTokensReceived();
    }

    function test_onTokensReceived_withExactAmount_succeeds() public {
        token.mint(address(custodyAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));

        vm.expectEmit(true, true, true, true, address(custodyAuction));
        emit IContinuousClearingAuction.TokensReceived(TOTAL_SUPPLY, CUSTODY_AMOUNT);
        custodyAuction.onTokensReceived();
    }

    function test_onTokensReceived_withExcess_succeeds() public {
        // Extra tokens beyond required should still work
        token.mint(address(custodyAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT) + 100e18);
        custodyAuction.onTokensReceived();
    }

    // ============================================
    // sweepUnsoldTokens — graduated auction
    // ============================================

    function test_sweepUnsoldTokens_graduated_includesCustodyTokens() public {
        _fundAndStartAuction();

        // Submit a bid large enough to graduate
        uint256 maxPrice = tickNumberToPriceX96(2);
        uint128 bidAmount = uint128(inputAmountForTokens(TOTAL_SUPPLY, maxPrice));
        vm.deal(alice, bidAmount);
        vm.prank(alice);
        uint256 bidId = custodyAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(custodyAuction.endBlock());
        custodyAuction.checkpoint();
        assertTrue(custodyAuction.isGraduated());

        uint256 totalCleared = custodyAuction.totalCleared();
        // unsoldTokens = TOTAL_SUPPLY - totalCleared + CUSTODY_AMOUNT
        uint256 expectedSweep;
        {
            uint256 totalSupplyQ96 = uint256(TOTAL_SUPPLY) << FixedPoint96.RESOLUTION;
            uint256 unsold = totalSupplyQ96.scaleUpToX7().saturatingSub(custodyAuction.totalClearedQ96_X7())
                .divUint256(FixedPoint96.Q96).scaleDownToUint256();
            expectedSweep = unsold + CUSTODY_AMOUNT;
        }

        uint256 recipientBalanceBefore = token.balanceOf(tokensRecipient);

        vm.prank(tokensRecipient);
        custodyAuction.sweepUnsoldTokens();

        uint256 recipientBalanceAfter = token.balanceOf(tokensRecipient);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, expectedSweep);
        // Custody tokens must be included
        assertGe(recipientBalanceAfter - recipientBalanceBefore, CUSTODY_AMOUNT);
    }

    function test_sweepUnsoldTokens_graduated_fullySold_sweepsCustodyOnly() public {
        _fundAndStartAuction();

        // Submit a massive bid to fully clear the auction
        uint256 maxPrice = tickNumberToPriceX96(10);
        uint128 bidAmount = uint128(inputAmountForTokens(TOTAL_SUPPLY, maxPrice));
        vm.deal(alice, bidAmount);
        vm.prank(alice);
        custodyAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(custodyAuction.endBlock());
        custodyAuction.checkpoint();
        assertTrue(custodyAuction.isGraduated());

        uint256 recipientBalanceBefore = token.balanceOf(tokensRecipient);

        vm.prank(tokensRecipient);
        custodyAuction.sweepUnsoldTokens();

        uint256 swept = token.balanceOf(tokensRecipient) - recipientBalanceBefore;
        // When fully sold, unsoldTokens ≈ 0 (just dust), so swept ≈ CUSTODY_AMOUNT
        assertApproxEqAbs(swept, CUSTODY_AMOUNT, MAX_ALLOWABLE_DUST_WEI);
    }

    // ============================================
    // sweepUnsoldTokens — non-graduated auction
    // ============================================

    function test_sweepUnsoldTokens_notGraduated_sweepsAllPlusCustody() public {
        _fundAndStartAuction();

        // Don't submit any bids — auction won't graduate
        vm.roll(custodyAuction.endBlock());

        uint256 recipientBalanceBefore = token.balanceOf(tokensRecipient);

        vm.prank(tokensRecipient);
        custodyAuction.sweepUnsoldTokens();

        uint256 swept = token.balanceOf(tokensRecipient) - recipientBalanceBefore;
        assertEq(swept, uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));
    }

    function test_sweepUnsoldTokens_notGraduated_withBids_sweepsAllPlusCustody() public {
        _fundAndStartAuction();

        // Submit a small bid that won't graduate
        custodyParams.requiredCurrencyRaised = type(uint128).max;
        ContinuousClearingAuction noGradAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
        token.mint(address(noGradAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));
        noGradAuction.onTokensReceived();

        vm.roll(noGradAuction.startBlock());
        uint256 maxPrice = tickNumberToPriceX96(2);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 bidId = noGradAuction.submitBid{value: 1 ether}(maxPrice, 1 ether, alice, bytes(''));

        vm.roll(noGradAuction.endBlock());
        // Exit bid — gets full refund since not graduated
        noGradAuction.exitBid(bidId);

        uint256 recipientBalanceBefore = token.balanceOf(tokensRecipient);

        vm.prank(tokensRecipient);
        noGradAuction.sweepUnsoldTokens();

        uint256 swept = token.balanceOf(tokensRecipient) - recipientBalanceBefore;
        assertEq(swept, uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));
    }

    // ============================================
    // Solvency — custody tokens don't affect auction math
    // ============================================

    function test_solvency_custodyTokensDontAffectClearing() public {
        _fundAndStartAuction();

        // Also deploy a zero-custody auction with identical params for comparison
        custodyParams.custodyTokens = 0;
        ContinuousClearingAuction baselineAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
        token.mint(address(baselineAuction), TOTAL_SUPPLY);
        baselineAuction.onTokensReceived();

        // Submit identical bids to both
        uint256 maxPrice = tickNumberToPriceX96(3);
        uint128 bidAmount = uint128(inputAmountForTokens(500e18, maxPrice));
        vm.deal(alice, bidAmount * 2);

        vm.startPrank(alice);
        custodyAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));
        baselineAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));
        vm.stopPrank();

        vm.roll(custodyAuction.endBlock());
        Checkpoint memory cpCustody = custodyAuction.checkpoint();
        Checkpoint memory cpBaseline = baselineAuction.checkpoint();

        // Clearing price, totalCleared, and currencyRaised must be identical
        assertEq(cpCustody.clearingPrice, cpBaseline.clearingPrice, 'clearing prices differ');
        assertEq(custodyAuction.totalCleared(), baselineAuction.totalCleared(), 'totalCleared differs');
        assertEq(custodyAuction.currencyRaised(), baselineAuction.currencyRaised(), 'currencyRaised differs');
    }

    function test_solvency_afterExitsClaimsAndSweep_onlyDustRemains() public {
        _fundAndStartAuction();

        // Submit multiple bids at different prices
        uint256 price2 = tickNumberToPriceX96(2);
        uint256 price5 = tickNumberToPriceX96(5);

        uint128 bid1Amount = uint128(inputAmountForTokens(300e18, price5));
        uint128 bid2Amount = uint128(inputAmountForTokens(700e18, price2));

        vm.deal(alice, bid1Amount);
        vm.deal(bob, bid2Amount);

        vm.prank(alice);
        uint256 bidId1 = custodyAuction.submitBid{value: bid1Amount}(price5, bid1Amount, alice, bytes(''));
        vm.prank(bob);
        uint256 bidId2 = custodyAuction.submitBid{value: bid2Amount}(price2, bid2Amount, bob, bytes(''));

        vm.roll(custodyAuction.endBlock());
        Checkpoint memory finalCp = custodyAuction.checkpoint();
        assertTrue(custodyAuction.isGraduated());

        // Exit bids
        if (price5 > finalCp.clearingPrice) {
            custodyAuction.exitBid(bidId1);
        } else {
            custodyAuction.exitPartiallyFilledBid(bidId1, custodyAuction.startBlock(), 0);
        }
        if (price2 > finalCp.clearingPrice) {
            custodyAuction.exitBid(bidId2);
        } else {
            custodyAuction.exitPartiallyFilledBid(bidId2, custodyAuction.startBlock(), 0);
        }

        // Sweep currency
        vm.prank(fundsRecipient);
        custodyAuction.sweepCurrency();

        // Sweep unsold + custody tokens
        vm.prank(tokensRecipient);
        custodyAuction.sweepUnsoldTokens();

        // Claim tokens
        vm.roll(custodyAuction.claimBlock());
        custodyAuction.claimTokens(bidId1);
        custodyAuction.claimTokens(bidId2);

        // Contract should only have dust remaining
        assertApproxEqAbs(
            token.balanceOf(address(custodyAuction)), 0, MAX_ALLOWABLE_DUST_WEI, 'token dust exceeds allowance'
        );
        assertApproxEqAbs(address(custodyAuction).balance, 0, MAX_ALLOWABLE_DUST_WEI, 'currency dust exceeds allowance');
    }

    // ============================================
    // lbpInitializationParams
    // ============================================

    function test_lbpInitializationParams_unaffectedByCustody() public {
        _fundAndStartAuction();

        // Deploy identical baseline auction without custody tokens
        custodyParams.custodyTokens = 0;
        ContinuousClearingAuction baselineAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
        token.mint(address(baselineAuction), TOTAL_SUPPLY);
        baselineAuction.onTokensReceived();

        // Submit identical bids
        uint256 maxPrice = tickNumberToPriceX96(3);
        uint128 bidAmount = uint128(inputAmountForTokens(500e18, maxPrice));
        vm.deal(alice, bidAmount * 2);

        vm.startPrank(alice);
        custodyAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));
        baselineAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));
        vm.stopPrank();

        vm.roll(custodyAuction.endBlock());
        custodyAuction.checkpoint();
        baselineAuction.checkpoint();

        LBPInitializationParams memory custodyLbp = custodyAuction.lbpInitializationParams();
        LBPInitializationParams memory baselineLbp = baselineAuction.lbpInitializationParams();

        assertEq(custodyLbp.initialPriceX96, baselineLbp.initialPriceX96, 'initialPriceX96 differs');
        assertEq(custodyLbp.tokensSold, baselineLbp.tokensSold, 'tokensSold differs');
        assertEq(custodyLbp.currencyRaised, baselineLbp.currencyRaised, 'currencyRaised differs');
    }

    // ============================================
    // Edge cases
    // ============================================

    function test_custodyTokens_zero_backwardCompatible() public {
        custodyParams.custodyTokens = 0;
        ContinuousClearingAuction zeroAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);

        // Only need TOTAL_SUPPLY
        token.mint(address(zeroAuction), TOTAL_SUPPLY);
        zeroAuction.onTokensReceived();

        vm.roll(zeroAuction.endBlock());

        vm.prank(tokensRecipient);
        zeroAuction.sweepUnsoldTokens();

        // Swept exactly TOTAL_SUPPLY (non-graduated, 0 custody)
        assertEq(token.balanceOf(tokensRecipient), TOTAL_SUPPLY);
    }

    function test_custodyTokens_largeCustodyAmount() public {
        // Custody can be larger than totalSupply
        uint128 largeCustody = type(uint128).max;
        custodyParams.custodyTokens = largeCustody;

        ContinuousClearingAuction largeAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);

        token.mint(address(largeAuction), uint256(TOTAL_SUPPLY) + uint256(largeCustody));
        largeAuction.onTokensReceived();

        vm.roll(largeAuction.endBlock());

        vm.prank(tokensRecipient);
        largeAuction.sweepUnsoldTokens();

        assertEq(token.balanceOf(tokensRecipient), uint256(TOTAL_SUPPLY) + uint256(largeCustody));
    }

    function test_custodyTokens_doesNotAffectBidSubmission() public {
        _fundAndStartAuction();

        // Bids should work identically — maxBidPrice based on TOTAL_SUPPLY only
        uint256 maxPrice = tickNumberToPriceX96(2);
        uint128 bidAmount = uint128(inputAmountForTokens(100e18, maxPrice));
        vm.deal(alice, bidAmount);

        vm.prank(alice);
        // Should not revert — custody tokens don't interfere with bidding
        custodyAuction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));
    }

    function test_custodyTokens_doesNotAffectGraduation() public {
        // requiredCurrencyRaised is independent of custodyTokens
        custodyParams.requiredCurrencyRaised = 1;
        custodyParams.custodyTokens = CUSTODY_AMOUNT;

        ContinuousClearingAuction gradAuction =
            new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, custodyParams);
        token.mint(address(gradAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));
        gradAuction.onTokensReceived();

        vm.roll(gradAuction.startBlock());
        uint256 maxPrice = tickNumberToPriceX96(2);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        gradAuction.submitBid{value: 1 ether}(maxPrice, 1 ether, alice, bytes(''));

        vm.roll(gradAuction.endBlock());
        gradAuction.checkpoint();
        assertTrue(gradAuction.isGraduated());
    }

    // ============================================
    // Helpers
    // ============================================

    function _fundAndStartAuction() internal {
        token.mint(address(custodyAuction), uint256(TOTAL_SUPPLY) + uint256(CUSTODY_AMOUNT));
        custodyAuction.onTokensReceived();
        vm.roll(custodyAuction.startBlock());
    }
}
