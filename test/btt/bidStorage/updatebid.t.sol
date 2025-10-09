// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, MockBidStorage} from 'btt/mocks/MockBidStorage.sol';

contract UpdateBidTest is BttBase {
    MockBidStorage public bidStorage;

    function setUp() external {
        bidStorage = new MockBidStorage();
    }

    function test_WhenCalledWithBidIdAndBid(Bid memory _bid, uint256 _bidId) external {
        // it overwrites bid[bidId] = bid
        // it overwrites bid[bidId].startBlock = bid.startBlock
        // it overwrites bid[bidId].startCumulativeMps = bid.startCumulativeMps
        // it overwrites bid[bidId].exitedBlock = bid.exitedBlock
        // it overwrites bid[bidId].maxPrice = bid.maxPrice
        // it overwrites bid[bidId].owner = bid.owner
        // it overwrites bid[bidId].amount = bid.amount
        // it overwrites bid[bidId].tokensFilled = bid.tokensFilled

        vm.record();
        bidStorage.updateBid(_bidId, _bid);
        (, bytes32[] memory writes) = vm.accesses(address(bidStorage));
        if (!isCoverage()) {
            assertEq(writes.length, 5);
        }

        Bid memory bidFromStorage = bidStorage.bids(_bidId);
        assertEq(bidFromStorage, _bid);
    }
}
