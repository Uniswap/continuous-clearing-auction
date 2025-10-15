// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, MockBidStorage} from 'btt/mocks/MockBidStorage.sol';

contract DeleteBidTest is BttBase {
    MockBidStorage public bidStorage;

    function setUp() external {
        bidStorage = new MockBidStorage();
    }

    function test_WhenCalledWithBidId(
        uint256 _amount,
        address _owner,
        uint256 _maxPrice,
        uint24 _startCumulativeMps,
        uint64 _blockNumber
    ) external {
        // it deletes the bid from storage
        // it overwrites bid[bidId].startBlock = 0
        // it overwrites bid[bidId].startCumulativeMps = 0
        // it overwrites bid[bidId].exitedBlock = 0
        // it overwrites bid[bidId].maxPrice = 0
        // it overwrites bid[bidId].owner = address(0)
        // it overwrites bid[bidId].amount = 0
        // it overwrites bid[bidId].tokensFilled = 0

        vm.roll(_blockNumber);
        (, uint256 bidId) = bidStorage.createBid(_amount, _owner, _maxPrice, _startCumulativeMps);

        vm.record();
        bidStorage.deleteBid(bidId);
        (, bytes32[] memory writes) = vm.accesses(address(bidStorage));

        // Five (5) writes to update the bid values to all 0
        if (!isCoverage()) {
            assertEq(writes.length, 5);
        }

        Bid memory bidFromStorage = bidStorage.bids(bidId);
        assertEq(bidFromStorage.startBlock, 0);
        assertEq(bidFromStorage.startCumulativeMps, 0);
        assertEq(bidFromStorage.exitedBlock, 0);
        assertEq(bidFromStorage.maxPrice, 0);
        assertEq(bidFromStorage.owner, address(0));
        assertEq(bidFromStorage.amountQ96, 0);
        assertEq(bidFromStorage.tokensFilled, 0);
    }
}
