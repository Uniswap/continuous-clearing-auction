// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {console2} from 'forge-std/console2.sol';
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

    function test_exitPartiallyFilledBid_outBid_notGraduated_succeeds(
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
        vm.expectRevert(IAuction.CannotPartiallyExitBidBeforeGraduation.selector);
        auction.exitPartiallyFilledBid(bidId1, startBlock, startBlock + 1);

        Bid memory bid1 = auction.bids(bidId1);
        assertEq(bid1.tokensFilled, 0);

        vm.roll(auction.endBlock());
        // Bid 1 can be exited as the auction is over
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidExited(bidId1, alice, 0, 1);
        auction.exitPartiallyFilledBid(bidId1, startBlock, startBlock + 1);
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

        uint256[] memory bids = helper__submitNBids(auction, alice, $bidAmount, _numberOfBids, $maxPrice);

        // Exit the bid
        vm.roll(auction.endBlock());
        for (uint256 i = 0; i < _numberOfBids; i++) {
            auction.exitBid(bids[i]);
        }

        // Go back to before the claim block
        vm.roll(auction.claimBlock() - 1);

        // Try to claim tokens before the claim block
        vm.expectRevert(IAuction.NotClaimable.selector);
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

    function test_concrete_expectedCurrencyRaisedGreaterThanBalance() public {
        bytes memory data =
            hex'3a8ded2200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000004d3ea885e732fb3c7408537a958800000000000000000000000000000000000000bc637f96249f00d971b5cf3ed800000000000000000000000000000000003c65a45b3d7b6470dca2aac1ec4f33000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000080000000000000000000000007e9b1cb4710a7f21eefc2681558d0c702bdbc523000000000000000000000000f0eead335a667799e40ec96f6dd2630ffc03675200000000000000000000000090a84bdbc08231da0516ad7265178c797887f5a1000000000000000000000000000000000000000000000000000000000000002d00000000000000000000000000000000000000000000000054bea095434774780000000000000000000000000000000000000000000000000000000000032678b71cba97ceead8c4c65b508988607541d88f5ccca28bba037e4777dfab1bdcf500000000000000000000000093dbd6b9b523830da3c17bc722f67d14748d8011000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000302d9be3a00f7365eb18ea8c8fd7c93b56ee449a110ff914ad496578b3476bd8341d6e00696d796e336367401834f7aebc00000000000000000000000000000000';
        (bool success, bytes memory result) = address(this).call(data);
        require(success, string(result));
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
            emit IAuction.TokensClaimed(bidId, alice, bid.tokensFilled);
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

    function test_concrete_clearingPriceRoundedUpToInitializedTick() public {
        bytes memory data =
            hex'8bd7b0ab0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000002b9740e8f776d98cd7e1e51af00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000d99eb98ebf2c31da1eb90704e12c7c617773261e000000000000000000000000192cb32e296602a504b481a685ee8f524b039d87000000000000000000000000bf6e9acdc3941d8add5b458cccaafc40cd4998ad000000000000000000000000000000000000000000000000000000000000019d000000000000000000000000000000000000000000000000fffffffffffffffe00000000000000000000000000000000000000000000000000000000000563160000000000000000000000000000000000000ac51ff0c51387d18feae2a2cd7900000000000000000000000072c61997f7d335a1fbbec447b5b492157e9d17e30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020b0000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000003ba32bbbc6536960e638037a17292eb87f4d46c426b158d06a52f5cf8831898cbf78deb9443147b1c1f13c66f72e34de564271d67d85dff6d18c85970000000000';
        (bool success, bytes memory result) = address(this).call(data);
        require(success, string(result));
    }

    function test_concrete_2() public {
        bytes memory data =
            hex'34d9075d0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000002b9740e8f776d98cd7e1e51af00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000002000000000000000000000000d99eb98ebf2c31da1eb90704e12c7c617773261e000000000000000000000000192cb32e296602a504b481a685ee8f524b039d87000000000000000000000000bf6e9acdc3941d8add5b458cccaafc40cd4998ad000000000000000000000000000000000000000000000000000000000000019d000000000000000000000000000000000000000000000000fffffffffffffffe00000000000000000000000000000000000000000000000000000000000563160000000000000000000000000000000000000ac51ff0c51387d18feae2a2cd7900000000000000000000000072c61997f7d335a1fbbec447b5b492157e9d17e30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020b0000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000003ba32bbbc6536960e638037a17292eb87f4d46c426b158d06a52f5cf8831898cbf78deb9443147b1c1f13c66f72e34de564271d67d85dff6d18c85970000000000';
        (bool success, bytes memory result) = address(this).call(data);
        require(success, string(result));
    }

    function test_concrete_3() public {
        bytes memory data =
            hex'a1100c05000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000ffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000fffffffffffffffffffffffffffffffd000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000080000000000000000000000007ba565603123244825e72ae643a8199175607f1900000000000000000000000055fadd1cf3fcfebb63d435229fafe4c7dfa52984000000000000000000000000a1810659071d9d3983d9ca4f1c2c7f9b358f4fc500000000000000000000000000000000000000000000000000000000000000bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000766f72000000068c3f2359a64686060ef2c0caedf83a36260fecd69e79aa9520641e4f0000000000000000000000000fba12ae53ad3242e721fa712ef94ec176e1a97d000000000000000000000032bf97ce06dcd1a6f8ae30cad8e3e628e71c03e4a30000000000000000000000000000000000000e872ebab52e639185131e010cc20000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000004100c2aa6455ea7191e77d3e993e2cf3135b48756ec4c11c20ca2893f689874ebc8eb6575c78634d31467ed5352f164f676ecee7d2835654cf6e16a61812e1d2c2b500000000000000000000000000000000000000000000000000000000000000';
        (bool success, bytes memory result) = address(this).call(data);
        require(success, string(result));
    }
}
