// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CheckpointStorage} from 'continuous-clearing-auction/CheckpointStorage.sol';

import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';

contract MockCheckpointStorage is CheckpointStorage {
    function insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) external {
        super._insertCheckpoint(checkpoint, blockNumber);
    }

    function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory) {
        return super._getCheckpoint(blockNumber);
    }
}
