// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';
import {FuzzDeploymentParams, FuzzBid} from '../utils/FuzzStructs.sol';
import {MockAuction} from '../utils/MockAuction.sol';

contract AuctionCalculateClearingPriceTest is AuctionBaseTest {
    MockAuction public mockAuction;

    function test_calculateClearingPrice(FuzzDeploymentParams memory _deploymentParams) public 
    setUpMockAuctionFuzz(_deploymentParams) {
        
    }
}