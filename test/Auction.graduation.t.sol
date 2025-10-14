// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';

import {console2} from 'forge-std/console2.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @dev These tests fuzz over the full range of inputs for both the auction parameters and the bids submitted
///      so we limit the number of fuzz runs.
/// forge-config: default.fuzz.runs = 500
/// forge-config: ci.fuzz.runs = 500
contract AuctionGraduationTest is AuctionBaseTest {
    using ValueX7Lib for *;
    using BidLib for *;

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
        auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());

        vm.prank(fundsRecipient);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auction.sweepCurrency();
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
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();
        uint256 expectedCurrencyRaised = auction.currencyRaised();

        uint256 aliceBalanceBefore = address(alice).balance;
        auction.exitBid(bidId);
        // Assert that no currency was refunded
        assertEq(address(alice).balance, aliceBalanceBefore);

        emit log_string('==================== SWEEP CURRENCY ====================');
        emit log_named_uint('auction balance', address(auction).balance);
        emit log_named_uint('bid amount', $bidAmount);
        emit log_named_uint('max price', $maxPrice);
        emit log_named_uint('final clearing price', finalCheckpoint.clearingPrice);
        emit log_named_uint('expectedCurrencyRaised', expectedCurrencyRaised);

        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, expectedCurrencyRaised);
        auction.sweepCurrency();

        // Verify funds were transferred
        assertEq(fundsRecipient.balance, expectedCurrencyRaised);
    }

    function test_concrete_expectedCurrencyRaisedGreaterThanBalance() public {
        bytes memory data = hex"3a8ded2200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000004d3ea885e732fb3c7408537a958800000000000000000000000000000000000000bc637f96249f00d971b5cf3ed800000000000000000000000000000000003c65a45b3d7b6470dca2aac1ec4f33000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000080000000000000000000000007e9b1cb4710a7f21eefc2681558d0c702bdbc523000000000000000000000000f0eead335a667799e40ec96f6dd2630ffc03675200000000000000000000000090a84bdbc08231da0516ad7265178c797887f5a1000000000000000000000000000000000000000000000000000000000000002d00000000000000000000000000000000000000000000000054bea095434774780000000000000000000000000000000000000000000000000000000000032678b71cba97ceead8c4c65b508988607541d88f5ccca28bba037e4777dfab1bdcf500000000000000000000000093dbd6b9b523830da3c17bc722f67d14748d8011000000000000000000000000000000000000000000000000000000000000006e0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000302d9be3a00f7365eb18ea8c8fd7c93b56ee449a110ff914ad496578b3476bd8341d6e00696d796e336367401834f7aebc00000000000000000000000000000000";
        (bool success, bytes memory result) = address(this).call(data);
        require(success, string(result));
    }

    function test_sweepUnsoldTokens_graduated(
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
    {
        auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        // Should sweep no tokens since graduated
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, 0);
        auction.sweepUnsoldTokens();
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
        auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        // Update the lastCheckpoint
        auction.checkpoint();

        // Should sweep ALL tokens since auction didn't graduate
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, $deploymentParams.totalSupply);
        auction.sweepUnsoldTokens();

        // Verify all tokens were transferred
        assertEq(token.balanceOf(tokensRecipient), $deploymentParams.totalSupply);
    }
}
