// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters} from '../src/interfaces/IAuction.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../src/libraries/ValueX7X7Lib.sol';

import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {console2} from 'forge-std/console2.sol';

contract AuctionSubmitBidTest is AuctionBaseTest {
    using BidLib for *;

    function test_submitBid_exactIn_succeeds_gas(FuzzDeploymentParams memory _deploymentParams, FuzzBid[] memory _bids)
        public
        setUpAuctionFuzz(_deploymentParams)
        setUpBidsFuzz(_bids)
        givenAuctionHasStarted
        givenExactIn
        givenFullyFundedAccount
    {
        uint256 expectedBidId;
        for (uint256 i = 0; i < _bids.length; i++) {
            // TODO(md): Temporary to ensure that we dont place bids that will not succeed if the clearing price moves above them during the tx
            auction.checkpoint();

            (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
            if (bidPlaced) expectedBidId++;

            helper__maybeRollToNextBlock(i);
        }
    }

    function test_submitBid_exactOut_succeeds_gas(FuzzDeploymentParams memory _deploymentParams, FuzzBid[] memory _bids)
        public
        setUpAuctionFuzz(_deploymentParams)
        setUpBidsFuzz(_bids)
        givenAuctionHasStarted
        givenExactOut
        givenFullyFundedAccount
    {
        uint256 expectedBidId;
        for (uint256 i = 0; i < _bids.length; i++) {
            // TODO(md): Temporary to ensure that we dont place bids that will not succeed if the clearing price moves above them during the tx
            auction.checkpoint();

            (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
            if (bidPlaced) expectedBidId++;

            helper__maybeRollToNextBlock(i);
        }
    }

    function test_submitBid_mixedExactInAndOut_succeeds_gas(
        FuzzDeploymentParams memory _deploymentParams,
        FuzzBid[] memory _bids
    ) public setUpAuctionFuzz(_deploymentParams) setUpBidsFuzz(_bids) givenAuctionHasStarted givenFullyFundedAccount {
        uint256 expectedBidId;
        for (uint256 i = 0; i < _bids.length; i++) {
            // TODO(md): Temporary to ensure that we dont place bids that will not succeed if the clearing price moves above them during the tx
            auction.checkpoint();

            $exactIn = block.number % 2 == 0;
            console2.log('exactIn', $exactIn);
            (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
            if (bidPlaced) expectedBidId++;

            helper__maybeRollToNextBlock(i);
        }
    }
}
