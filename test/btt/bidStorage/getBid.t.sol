// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, MockBidStorage} from 'btt/mocks/MockBidStorage.sol';
import {IBidStorage} from 'twap-auction/interfaces/IBidStorage.sol';

contract GetBidTest is BttBase {
    MockBidStorage public bidStorage;

    function setUp() external {
        bidStorage = new MockBidStorage();
    }

    function test_WhenBidDoesNotExist(uint256 _bidId) external {
        // it reverts with {BidIdDoesNotExist}

        vm.expectRevert(abi.encodeWithSelector(IBidStorage.BidIdDoesNotExist.selector, _bidId));
        bidStorage.getBid(_bidId);
    }

    function test_WhenBidExists(
        uint256 _amount,
        address _owner,
        uint256 _maxPrice,
        uint24 _startCumulativeMps,
        uint64 _blockNumber
    ) external {
        // it returns the bid

        Bid memory expectedBid = Bid({
            startBlock: _blockNumber,
            startCumulativeMps: _startCumulativeMps,
            exitedBlock: 0,
            maxPrice: _maxPrice,
            owner: _owner,
            amountQ96: _amount,
            tokensFilled: 0
        });

        vm.roll(_blockNumber);
        (, uint256 bidId) = bidStorage.createBid(_amount, _owner, _maxPrice, _startCumulativeMps);

        Bid memory bid = bidStorage.getBid(bidId);
        assertEq(bid, expectedBid);
    }
}
