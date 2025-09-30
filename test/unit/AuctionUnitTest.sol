// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/interfaces/IAuction.sol';

import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {MockAuction} from '../utils/MockAuction.sol';

contract AuctionUnitTest is AuctionBaseTest {
    MockAuction public mockAuction;

    /// @dev Sets up the auction for fuzzing, ensuring valid parameters
    modifier setUpMockAuctionFuzz(FuzzDeploymentParams memory _deploymentParams) {
        setUpMockAuction(_deploymentParams);
        _;
    }

    function setUpMockAuction(FuzzDeploymentParams memory _deploymentParams) public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        params = helper__validFuzzDeploymentParams(_deploymentParams);
        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_deploymentParams.auctionParams.floorPrice);
        mockAuction = new MockAuction(address(token), _deploymentParams.totalSupply, params);

        token.mint(address(mockAuction), _deploymentParams.totalSupply);
        mockAuction.onTokensReceived();
    }
}
