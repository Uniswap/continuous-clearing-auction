// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CheckpointStorage} from '../../src/CheckpointStorage.sol';
import {Bid} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';

contract MockCheckpointStorage is CheckpointStorage {
    function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory) {
        return _getCheckpoint(blockNumber);
    }

    function insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) external {
        _insertCheckpoint(checkpoint, blockNumber);
    }

    function calculateFill(
        Bid memory bid,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) external pure returns (uint128 tokensFilled, uint128 currencySpent) {
        return _calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, mpsDenominator);
    }
}
