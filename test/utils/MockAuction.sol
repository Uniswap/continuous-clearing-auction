// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(uint256 minimumClearingPrice, uint128 blockTokenSupply)
        external
        view
        returns (uint256)
    {
        // TODO: needs to be in mps terms
        return _calculateNewClearingPrice(sumDemandAboveClearing, minimumClearingPrice, blockTokenSupply);
    }

    /// @notice Helper function to insert a checkpoint
    function insertCheckpoint(Checkpoint memory _checkpoint, uint64 blockNumber) external {
        _insertCheckpoint(_checkpoint, blockNumber);
    }

    function getBid(uint256 bidId) external view returns (Bid memory) {
        return _getBid(bidId);
    }

    function createBid(bool exactIn, uint128 amount, address owner, uint256 maxPrice) external returns (uint256) {
        return _createBid(exactIn, amount, owner, maxPrice);
    }
}
