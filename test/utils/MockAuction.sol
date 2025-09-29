// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';

import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {SupplyLib, SupplyRolloverMultiplier} from '../../src/libraries/SupplyLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(
        uint256 minimumClearingPrice,
        uint24 remainingMpsInAuction,
        ValueX7X7 remainingSupplyX7X7
    ) external view returns (uint256) {
        return _calculateNewClearingPrice(minimumClearingPrice, remainingMpsInAuction, remainingSupplyX7X7);
    }

    function unpackSupplyRolloverMultiplier()
        external
        view
        returns (bool isSet, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
    {
        return SupplyLib.unpack($_supplyRolloverMultiplier);
    }

    function setSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7) external {
        $_supplyRolloverMultiplier = SupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
    }

    /// @notice Helper function to insert a checkpoint
    function insertCheckpoint(Checkpoint memory _checkpoint, uint64 blockNumber) external {
        _insertCheckpoint(_checkpoint, blockNumber);
    }

    function getBid(uint256 bidId) external view returns (Bid memory) {
        return _getBid(bidId);
    }

    function createBid(bool exactIn, uint128 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        external
        returns (Bid memory, uint256)
    {
        return _createBid(exactIn, amount, owner, maxPrice, startCumulativeMps);
    }
}
