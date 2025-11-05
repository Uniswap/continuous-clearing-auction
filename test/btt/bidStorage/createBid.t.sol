// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, MockBidStorage} from 'btt/mocks/MockBidStorage.sol';

contract CreateBidTest is BttBase {
    MockBidStorage public bidStorage;

    function setUp() external {
        bidStorage = new MockBidStorage();
    }

    function test_WhenCalledWithParams(
        uint256 _amount,
        address _owner,
        uint256 _maxPrice,
        uint24 _startCumulativeMps,
        uint64 _blockNumber
    ) external {
        // it creates a new bid with the given parameters
        // it has bid.startBlock = current block number
        // it has bid.startCumulativeMps = startCumulativeMps
        // it has bid.exitedBlock = 0
        // it has bid.maxPrice = maxPrice
        // it has bid.owner = owner
        // it has bid.amount = amount
        // it has bid.tokensFilled = 0
        // it caches bidId = $_nextBidId
        // it writes the bid to storage at bidId
        // it increments $_nextBidId
        // it returns the bid and the bid id

        vm.roll(_blockNumber);
        vm.record();
        (Bid memory bid, uint256 bidId) = bidStorage.createBid(_amount, _owner, _maxPrice, _startCumulativeMps);

        (, bytes32[] memory writes) = vm.accesses(address(bidStorage));

        // One (1) write to update the next bid id
        // Five (5) writes to update the bid
        if (!isCoverage()) {
            assertEq(writes.length, 6);
        }

        assertEq(bidId, 0);
        assertEq(bidStorage.nextBidId(), bidId + 1);

        Bid memory bidFromStorage = bidStorage.bids(bidId);
        assertEq(bidFromStorage.startBlock, _blockNumber);
        assertEq(bidFromStorage.startCumulativeMps, _startCumulativeMps);
        assertEq(bidFromStorage.exitedBlock, 0);
        assertEq(bidFromStorage.maxPrice, _maxPrice);
        assertEq(bidFromStorage.owner, _owner);
        assertEq(bidFromStorage.amountQ96, _amount);
        assertEq(bidFromStorage.tokensFilled, 0);

        assertEq(bid, bidFromStorage);
        assertEq(bid, bidStorage.getBid(bidId));
    }
}
