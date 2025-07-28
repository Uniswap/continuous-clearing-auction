// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Checkpoint {
    uint256 clearingPrice;
    uint256 blockCleared;
    uint256 totalCleared;
    uint24 cumulativeMps;
    uint256 cumulativeMpsPerPrice;
    uint256 prev;
}

abstract contract CheckpointStorage {
    mapping(uint256 blockNumber => Checkpoint) private checkpoints;
    uint256 public lastCheckpointedBlock;

    function latestCheckpoint() public view returns (Checkpoint memory) {
        return checkpoints[lastCheckpointedBlock];
    }

    function _getCheckpoint(uint256 blockNumber) internal view returns (Checkpoint memory) {
        return checkpoints[blockNumber];
    }

    function _insertCheckpoint(Checkpoint memory checkpoint) internal {
        checkpoints[block.number] = checkpoint;
        lastCheckpointedBlock = block.number;
    }
}
