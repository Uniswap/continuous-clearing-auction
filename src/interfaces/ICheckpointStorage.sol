// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../libraries/CheckpointLib.sol';

/// @notice Interface for checkpoint storage operations
interface ICheckpointStorage {
    /// @notice Get the latest checkpoint at the last checkpointed block
    /// @dev Be aware that the latest checkpoint may not be up to date, it is recommended
    ///      to always call `checkpoint()` before using getter functions
    /// @return The latest checkpoint
    function latestCheckpoint() external view returns (Checkpoint memory);

    /// @notice Get the clearing price at the last checkpointed block
    /// @dev Be aware that the latest checkpoint may not be up to date, it is recommended
    ///      to always call `checkpoint()` before using getter functions
    /// @return The current clearing price in Q96 form
    function clearingPrice() external view returns (uint256);

    /// @notice Get the number of the last checkpointed block
    /// @dev Be aware that the last checkpointed block may not be up to date, it is recommended
    ///      to always call `checkpoint()` before using getter functions
    /// @return The block number of the last checkpoint
    function lastCheckpointedBlock() external view returns (uint64);

    /// @notice Get a checkpoint at a block number
    function checkpoints(uint64 blockNumber) external view returns (Checkpoint memory);
}
