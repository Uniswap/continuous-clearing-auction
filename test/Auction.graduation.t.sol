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
        assumeSubmitBid($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

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
        assumeSubmitBid($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

        vm.roll(auction.endBlock());
        auction.checkpoint();
        uint256 expectedCurrencyRaised = auction.currencyRaised();

        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, expectedCurrencyRaised);
        auction.sweepCurrency();

        // Verify funds were transferred
        assertEq(fundsRecipient.balance, expectedCurrencyRaised);
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
        assumeSubmitBid($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

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
        assumeSubmitBid($maxPrice, $bidAmount, alice, params.floorPrice, bytes(''));

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
