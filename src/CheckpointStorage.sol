// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICheckpointStorage} from './interfaces/ICheckpointStorage.sol';
import {Checkpoint} from './libraries/CheckpointLib.sol';

/// @title CheckpointStorage
/// @notice Abstract contract for managing auction checkpoints
abstract contract CheckpointStorage is ICheckpointStorage {
    /// @notice Maximum block number value used as sentinel for last checkpoint
    uint64 public constant MAX_BLOCK_NUMBER = type(uint64).max;

    /// @notice Storage of checkpoints
    mapping(uint64 blockNumber => Checkpoint) private $_checkpoints;
    /// @notice The block number of the last checkpointed block
    uint64 internal $lastCheckpointedBlock;

    /// @inheritdoc ICheckpointStorage
    function latestCheckpoint() public view returns (Checkpoint memory) {
        return _getCheckpoint($lastCheckpointedBlock);
    }

    /// @notice Get a checkpoint from storage
    function _getCheckpoint(uint64 blockNumber) internal view returns (Checkpoint memory) {
        return $_checkpoints[blockNumber];
    }

    /// @notice Insert a checkpoint into storage
    /// @dev This function updates the prev and next pointers of the latest checkpoint and the new checkpoint
    function _insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) internal {
        uint64 _lastCheckpointedBlock = $lastCheckpointedBlock;
        // Enforce strictly increasing checkpoint block numbers
        if (blockNumber <= _lastCheckpointedBlock) revert CheckpointBlockNotIncreasing();
        // Link new checkpoint to the previous checkpoint
        checkpoint.prev = _lastCheckpointedBlock;
        checkpoint.next = MAX_BLOCK_NUMBER;
        // Link previous checkpoint to the new checkpoint
        $_checkpoints[_lastCheckpointedBlock].next = blockNumber;
        // Write the new checkpoint
        $_checkpoints[blockNumber] = checkpoint;
        // Update the last checkpointed block
        $lastCheckpointedBlock = blockNumber;
    }

    /// @inheritdoc ICheckpointStorage
    function lastCheckpointedBlock() external view returns (uint64) {
        return $lastCheckpointedBlock;
    }

    /// @inheritdoc ICheckpointStorage
    function checkpoints(uint64 blockNumber) external view returns (Checkpoint memory) {
        return $_checkpoints[blockNumber];
    }
}
