// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BidStorage} from '../src/BidStorage.sol';

import {IBidStorage} from '../src/interfaces/IBidStorage.sol';
import {Bid} from '../src/libraries/BidLib.sol';
import {Assertions} from './utils/Assertions.sol';
import {Test} from 'forge-std/Test.sol';

contract MockBidStorage is BidStorage {
    function getBid(uint256 bidId) external view returns (Bid memory) {
        return _getBid(bidId);
    }

    function createBid(uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        external
        returns (Bid memory, uint256)
    {
        return _createBid(amount, owner, maxPrice, startCumulativeMps);
    }
}

contract BidStorageTest is Assertions, Test {
    MockBidStorage public mockBidStorage;

    function setUp() public {
        mockBidStorage = new MockBidStorage();
    }

    function helper__createBid(uint256 _amount, address _owner, uint256 _maxPrice, uint24 _startCumulativeMps)
        public
        returns (Bid memory, uint256)
    {
        return mockBidStorage.createBid(_amount, _owner, _maxPrice, _startCumulativeMps);
    }

    function helper__createBid(Bid memory _bid) public returns (Bid memory, uint256) {
        return mockBidStorage.createBid(_bid.amountQ96, _bid.owner, _bid.maxPrice, _bid.startCumulativeMps);
    }

    function hash(Bid memory _bid) public pure returns (bytes32) {
        return keccak256(abi.encode(_bid));
    }

    function assertEq(Bid memory _bid, Bid memory _expectedBid) public pure {
        assertEq(hash(_bid), hash(_expectedBid));
    }

    function test_createBid_succeeds(uint256 _amount, address _owner, uint256 _maxPrice, uint24 _startCumulativeMps)
        public
    {
        (Bid memory bid, uint256 bidId) = mockBidStorage.createBid(_amount, _owner, _maxPrice, _startCumulativeMps);
        assertEq(mockBidStorage.getBid(bidId), bid);
    }

    function test_getBid_revertsIfBidDoesNotExist(uint256 _bidId) public {
        vm.assume(_bidId >= mockBidStorage.nextBidId());
        vm.expectRevert(IBidStorage.BidIdDoesNotExist.selector);
        mockBidStorage.getBid(_bidId);
    }

    function test_bids_revertsIfBidDoesNotExist(uint256 _bidId) public {
        vm.assume(_bidId >= mockBidStorage.nextBidId());
        vm.expectRevert(IBidStorage.BidIdDoesNotExist.selector);
        mockBidStorage.bids(_bidId);
    }
}
