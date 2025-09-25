// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';

import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ValueX7} from '../../src/libraries/MPSLib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(uint256 minimumClearingPrice, ValueX7 blockTokenSupply)
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

    function createBid(bool exactIn, uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        external
        returns (Bid memory, uint256)
    {
        return _createBid(exactIn, amount, owner, maxPrice, startCumulativeMps);
    }
}
