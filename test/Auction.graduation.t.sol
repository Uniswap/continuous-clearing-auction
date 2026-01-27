// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {CheckpointAccountingLib} from '../src/libraries/CheckpointAccountingLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @dev These tests fuzz over the full range of inputs for both the auction parameters and the bids submitted
///      so we limit the number of fuzz runs.
/// forge-config: default.fuzz.runs = 1000
contract AuctionGraduationTest is AuctionBaseTest {
    using ValueX7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    function test_exitBid_graduated_succeeds(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();

        if ($maxPrice > finalCheckpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, auction.startBlock(), 0);
        }

        vm.roll(auction.claimBlock());
        uint256 aliceTokensBefore = token.balanceOf(alice);
        auction.claimTokens(bidId);
        assertApproxEqAbs(
            auction.totalCleared(),
            token.balanceOf(alice) - aliceTokensBefore,
            MAX_ALLOWABLE_DUST_WEI,
            'Total cleared must be within 1e18 wei of the tokens filled by alice'
        );
    }

    function test_exitBid_notGraduated_succeeds(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenNotGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsNotGraduated
        checkAuctionIsSolvent
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        uint256 aliceBalanceBefore = address(alice).balance;
        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Expect 100% refund since the auction did not graduate
        assertEq(address(alice).balance, aliceBalanceBefore + $bidAmount);
    }

    /// forge-config: default.fuzz.runs = 200
    function test_exitPartiallyFilledBid_outBid_notGraduated_succeeds(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint256 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenNotGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsNotGraduated
        checkAuctionIsSolvent
    {
        uint64 startBlock = auction.startBlock();
        uint256 lowPrice = helper__roundPriceUpToTickSpacing(params.floorPrice + 1, params.tickSpacing);
        uint256 bidId1 = auction.submitBid{value: 1}(lowPrice, 1, alice, params.floorPrice, bytes(''));
        vm.assume($maxPrice > lowPrice);
        auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(block.number + 1);
        // Assume that the auction is not over
        vm.assume(block.number < auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        vm.assume(checkpoint.clearingPrice > lowPrice);
        assertFalse(auction.isGraduated());
        // Exit the first bid which is now outbid
        vm.expectRevert(IContinuousClearingAuction.CannotPartiallyExitBidBeforeGraduation.selector);
        auction.exitPartiallyFilledBid(bidId1, startBlock, startBlock + 1);

        Bid memory bid1 = auction.bids(bidId1);
        assertEq(bid1.tokensFilled, 0);

        vm.roll(auction.endBlock());
        // Bid 1 can be exited as the auction is over
        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.BidExited(bidId1, alice, 0, 1);
        auction.exitPartiallyFilledBid(bidId1, startBlock, startBlock + 1);
    }

    /// @notice Fuzzy helper function to get the required amount to move the clearing price to the target price
    /// @dev Note that depending on the total supply / mps configurations it may not be possible to hit this scenario
    ///      so we use vm.assume to force the scenario to be hit. This will fail in higher fuzz run tests
    function _getRequiredAmountToMoveClearingToPrice(
        uint256 totalSupply,
        uint256 price,
        uint128 existingBidAmount,
        uint24 cumulativeMps
    ) internal pure returns (uint128 requiredAmount) {
        uint256 existingBidAmountQ96 = uint256(existingBidAmount) << FixedPoint96.RESOLUTION;
        // find the price just under the target price
        uint256 targetDemandQ96 = (totalSupply * (price - 1)) + 1;
        // find the price just above the target price
        uint256 upperBoundDemandQ96 = (totalSupply * price) - 1;
        uint24 remainingMps = ConstantsLib.MPS - cumulativeMps;
        // find the required amount, considering the remaining mps in the auction
        uint256 requiredAmountQ96 =
            (targetDemandQ96 - existingBidAmountQ96).fullMulDivUp(remainingMps, ConstantsLib.MPS);
        // go from Q96 to uint128
        requiredAmount = SafeCastLib.toUint128(requiredAmountQ96 >> FixedPoint96.RESOLUTION);
        if (requiredAmount == 0) requiredAmount = 1;

        uint256 effectiveRequiredAmount =
            (uint256(requiredAmount) << FixedPoint96.RESOLUTION) * ConstantsLib.MPS / remainingMps;
        uint256 sumDemandQ96 = existingBidAmountQ96 + effectiveRequiredAmount;

        uint256 iterations;
        while ((sumDemandQ96 < targetDemandQ96 || sumDemandQ96 > upperBoundDemandQ96) && iterations < 10) {
            if (sumDemandQ96 < targetDemandQ96) {
                requiredAmount += 1;
            } else {
                uint256 excess = sumDemandQ96 - upperBoundDemandQ96;
                uint256 reduceQ96 = excess.fullMulDivUp(remainingMps, ConstantsLib.MPS);
                uint256 reduceAmount = reduceQ96 >> FixedPoint96.RESOLUTION;
                if (reduceAmount == 0) reduceAmount = 1;
                if (reduceAmount >= requiredAmount) {
                    requiredAmount = 1;
                } else {
                    requiredAmount -= SafeCastLib.toUint128(reduceAmount);
                }
            }
            effectiveRequiredAmount =
                (uint256(requiredAmount) << FixedPoint96.RESOLUTION) * ConstantsLib.MPS / remainingMps;
            sumDemandQ96 = existingBidAmountQ96 + effectiveRequiredAmount;
            iterations++;
        }
        // It's possible that given the parameters we can't hit this scenario so we throw out those runs
        vm.assume(targetDemandQ96 <= sumDemandQ96 && sumDemandQ96 <= upperBoundDemandQ96);
    }

    /// forge-config: default.fuzz.runs = 100
    /// forge-config: ci.fuzz.runs = 100
    /// @dev This test requires to be run with a low fuzz run count.
    function test_exitPartiallyFilledBid_WhenAllCurrencyIsSpent(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        vm.assume($maxPrice < auction.MAX_BID_PRICE() - auction.tickSpacing()); // allow for at least 2 bids above floor
        vm.assume(auction.endBlock() - auction.startBlock() > 3); // allow for at least 4 checkpoints

        uint64 startBlock = auction.startBlock();
        // bid amount is half of the exact amount that would be needed to fill the auction
        uint256 totalSupply = auction.totalSupply();
        $bidAmount = uint128(totalSupply.fullMulDivUp($maxPrice, FixedPoint96.Q96) / 2);
        vm.assume($bidAmount > 0);
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(block.number + 1);
        Checkpoint memory checkpoint = auction.checkpoint();
        assertLt(
            checkpoint.clearingPrice,
            $maxPrice,
            'test setup failed: checkpoint.clearingPrice must be less than $maxPrice'
        );
        vm.assume(checkpoint.cumulativeMps < ConstantsLib.MPS);

        uint128 requiredAmount =
            _getRequiredAmountToMoveClearingToPrice(totalSupply, $maxPrice, $bidAmount, checkpoint.cumulativeMps);

        uint256 nextBidId = auction.submitBid{value: requiredAmount}(
            $maxPrice + auction.tickSpacing(), requiredAmount, alice, params.floorPrice, bytes('')
        );

        /**
         * Scenario:
         * - the auction finishes at the first bid's maxPrice
         * - the first bid participated for the entirety of the auction
         * - the second bid is higher, but is not enough to move the clearing price there
         * - the second bid amount is perfectly sized to evenly split the tokens with the first bid
         * - thus, the first bid spends 100% of its currency
         */
        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();
        // Assert that the auction finishes at the first maxPrice
        assertEq(auction.clearingPrice(), $maxPrice);

        // Locally validate that for the first bid, the sum of the individual sections would overflow the original bid amount
        Bid memory bid = auction.bids(bidId);
        (, uint256 fullySpentQ96) = CheckpointAccountingLib.accountFullyFilledCheckpoints(
            auction.checkpoints(startBlock + 1), auction.checkpoints(startBlock), bid
        );
        (, uint256 partialSpentQ96) = CheckpointAccountingLib.accountPartiallyFilledCheckpoints(
            bid, auction.ticks($maxPrice).currencyDemandQ96, finalCheckpoint.currencyRaisedAtClearingPriceQ96_X7
        );
        uint256 totalSpentQ96 = fullySpentQ96 + partialSpentQ96;

        // In some cases the total spent and amount are equal (due to variable rounding), so assume that its >
        vm.assume(totalSpentQ96 > bid.amountQ96);

        // Assert that the first bid cannot be exited via exitBid
        vm.expectRevert(IContinuousClearingAuction.CannotExitBid.selector);
        auction.exitBid(bidId);

        // Assert that the first bid can be exited via exitPartiallyFilledBid
        uint256 balanceBefore = address(alice).balance;
        auction.exitPartiallyFilledBid(bidId, startBlock + 1, 0);

        // Assert that all of the currency was spent, so refund is 0
        assertEq(address(alice).balance, balanceBefore + 0);

        // Assert that the second bid can be exited via exitBid
        auction.exitBid(nextBidId);

        vm.roll(auction.claimBlock());
        // Claim all tokens
        auction.claimTokens(bidId);
        auction.claimTokens(nextBidId);
    }

    function test_claimTokensBatch_notGraduated_reverts(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice,
        uint128 _numberOfBids
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenNotGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsNotGraduated
    {
        // Dont do too many bids
        _numberOfBids = SafeCastLib.toUint128(_bound(_numberOfBids, 1, 10));

        // Ensure an amount of at least 1 for every bid
        $bidAmount = uint128(bound(_bidAmount, _numberOfBids, type(uint128).max));
        // Ensure the graduation threshold is not met
        vm.assume($bidAmount < params.requiredCurrencyRaised);

        uint256[] memory bids = helper__submitNBids(auction, alice, $bidAmount, _numberOfBids, $maxPrice);

        // Exit the bid
        vm.roll(auction.endBlock());
        for (uint256 i = 0; i < _numberOfBids; i++) {
            auction.exitBid(bids[i]);
        }

        // Go back to before the claim block
        vm.roll(auction.claimBlock() - 1);

        // Try to claim tokens before the claim block
        vm.expectRevert(IContinuousClearingAuction.NotClaimable.selector);
        auction.claimTokensBatch(alice, bids);
    }

    function test_sweepCurrency_notGraduated_reverts(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenNotGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsNotGraduated
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        auction.checkpoint();
        uint256 expectedCurrencyRaised = auction.currencyRaised();
        uint256 expectedCurrencyRaisedFromCheckpoint =
            auction.currencyRaisedQ96_X7().scaleDownToUint256() >> FixedPoint96.RESOLUTION;

        vm.prank(fundsRecipient);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auction.sweepCurrency();

        emit log_string('===== Auction is NOT graduated =====');
        emit log_named_uint('currencyRaised in final checkpoint', expectedCurrencyRaisedFromCheckpoint);
        emit log_named_uint('balance before refunds', address(auction).balance);
        emit log_named_uint('currencyRaised', expectedCurrencyRaised);
        // Expected currency raised MUST always be less than or equal to the balance since it did not graduate
        assertLe(expectedCurrencyRaised, address(auction).balance);
        // Process refunds
        auction.exitBid(bidId);
        emit log_named_uint('balance after refunds', address(auction).balance);
        // Assert that the balance is zero since it did not graduate
        assertEq(address(auction).balance, 0);
    }

    function test_sweepCurrency_graduated_succeeds(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        uint64 bidIdBlock = uint64(block.number);
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        if ($maxPrice > finalCheckpoint.clearingPrice) {
            auction.exitBid(bidId);
            // Assert that no currency was refunded
            assertEq(address(alice).balance, aliceBalanceBefore);
        } else {
            auction.exitPartiallyFilledBid(bidId, bidIdBlock, 0);
        }

        vm.roll(auction.claimBlock());
        uint256 aliceTokensBefore = token.balanceOf(alice);
        auction.claimTokens(bidId);
        assertApproxEqAbs(
            token.balanceOf(alice),
            aliceTokensBefore + auction.totalCleared(),
            MAX_ALLOWABLE_DUST_WEI,
            'Total cleared must be within 1e18 wei of the tokens filled by alice'
        );
    }

    function test_sweepUnsoldTokens_graduated_sweepsLeftoverTokens(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        uint64 bidBlock = uint64(_bound(block.number, auction.startBlock(), auction.endBlock() - 1));
        vm.roll(bidBlock);
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();

        vm.assume(auction.isGraduated());

        if ($maxPrice > finalCheckpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, bidBlock, 0);
        }

        Bid memory bid = auction.bids(bidId);
        assertLe(bid.tokensFilled, auction.totalCleared());

        vm.roll(auction.claimBlock());
        uint256 aliceTokensBefore = token.balanceOf(alice);

        if (bid.tokensFilled > 0) {
            vm.expectEmit(true, true, true, true);
            emit IContinuousClearingAuction.TokensClaimed(bidId, alice, bid.tokensFilled);
            auction.claimTokens(bidId);
            assertEq(token.balanceOf(alice), bid.tokensFilled);
        }

        assertApproxEqAbs(
            auction.totalCleared(),
            token.balanceOf(alice) - aliceTokensBefore,
            MAX_ALLOWABLE_DUST_WEI,
            'Total cleared must be within 1e18 wei of the tokens filled by alice'
        );
    }

    function test_sweepUnsoldTokens_notGraduated(
        FuzzDeploymentParams memory _deploymentParams,
        uint128 _bidAmount,
        uint128 _maxPrice
    )
        public
        setUpAuctionFuzz(_deploymentParams)
        givenValidMaxPriceWithParams(_maxPrice, $deploymentParams.totalSupply, params.floorPrice, params.tickSpacing)
        givenValidBidAmount(_bidAmount)
        givenNotGraduatedAuction
        givenAuctionHasStarted
        givenFullyFundedAccount
        checkAuctionIsNotGraduated
    {
        uint64 bidBlock = uint64(_bound(block.number, auction.startBlock(), auction.endBlock() - 1));
        vm.roll(bidBlock);
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        // Update the lastCheckpoint
        Checkpoint memory checkpoint = auction.checkpoint();

        // Should sweep ALL tokens since auction didn't graduate
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, $deploymentParams.totalSupply);
        auction.sweepUnsoldTokens();

        // Verify all tokens were transferred
        assertEq(token.balanceOf(tokensRecipient), $deploymentParams.totalSupply);

        uint256 expectedCurrencyRaised = auction.currencyRaised();
        uint256 expectedCurrencyRaisedFromCheckpoint =
            auction.currencyRaisedQ96_X7().scaleDownToUint256() >> FixedPoint96.RESOLUTION;

        emit log_string('===== Auction is NOT graduated =====');
        emit log_named_uint('currencyRaised in final checkpoint', expectedCurrencyRaisedFromCheckpoint);
        emit log_named_uint('balance before refunds', address(auction).balance);
        emit log_named_uint('currencyRaised', expectedCurrencyRaised);
        // Expected currency raised MUST always be less than or equal to the balance since it did not graduate
        assertLe(expectedCurrencyRaised, address(auction).balance);
        // Process refunds
        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, bidBlock, 0);
        }
        emit log_named_uint('balance after refunds', address(auction).balance);
        // Assert that the balance is zero since it did not graduate
        assertEq(address(auction).balance, 0);
    }
}
