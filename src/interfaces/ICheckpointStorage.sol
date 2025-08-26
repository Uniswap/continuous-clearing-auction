// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../libraries/CheckpointLib.sol';

interface ICheckpointStorage {
    /// @notice Get the latest checkpoint at the last checkpointed block
    function latestCheckpoint() external view returns (Checkpoint memory);

    /// @notice Get the clearing price at the last checkpointed block
    function clearingPrice() external view returns (uint256);

    /// @notice Get the number of the last checkpointed block
    function lastCheckpointedBlock() external view returns (uint256);
}
