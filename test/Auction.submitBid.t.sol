// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';
import {AuctionParameters} from '../src/interfaces/IAuction.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {console2} from 'forge-std/console2.sol';

contract AuctionSubmitBidTest is AuctionBaseTest {
    using BidLib for *;

    /// forge-config: default.fuzz.runs = 1000
    function test_submitBid_exactIn_succeeds(FuzzDeploymentParams memory _deploymentParams, FuzzBid[] memory _bids)
        public
        setUpAuctionFuzz(_deploymentParams)
        setUpBidsFuzz(_bids)
        givenAuctionHasStarted
        givenFullyFundedAccount
    {
        uint256 expectedBidId;
        for (uint256 i = 0; i < _bids.length; i++) {
            (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
            if (bidPlaced) expectedBidId++;

            helper__maybeRollToNextBlock(i);
        }
    }

    function test_submitBid_revertsWithInvalidBidPriceTooHigh(
        FuzzDeploymentParams memory _deploymentParams,
        uint256 _maxPrice
    ) public setUpAuctionFuzz(_deploymentParams) givenAuctionHasStarted givenFullyFundedAccount {
        // Assume there is at least one tick that is above the MAX_BID_PRICE and type(uint256).max
        vm.assume(auction.MAX_BID_PRICE() < helper__roundPriceDownToTickSpacing(type(uint256).max, params.tickSpacing));
        _maxPrice = _bound(
            _maxPrice,
            helper__roundPriceUpToTickSpacing(auction.MAX_BID_PRICE() + 1, params.tickSpacing),
            type(uint256).max
        );
        _maxPrice = helper__roundPriceDownToTickSpacing(_maxPrice, params.tickSpacing);
        vm.expectRevert(IAuction.InvalidBidPriceTooHigh.selector);
        auction.submitBid{value: 1}(_maxPrice, 1, alice, params.floorPrice, bytes(''));
    }

    function test_submitBid_revertsWithBidOwnerCannotBeZeroAddress(FuzzDeploymentParams memory _deploymentParams)
        public
        setUpAuctionFuzz(_deploymentParams)
        givenAuctionHasStarted
        givenFullyFundedAccount
    {
        vm.expectRevert(IAuction.BidOwnerCannotBeZeroAddress.selector);
        auction.submitBid{value: 1}(1, 1, address(0), params.floorPrice, bytes(''));
    }
}
