// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../libraries/CheckpointLib.sol';

/// @notice Interface for checkpoint storage operations
interface ICheckpointStorage {
    /// @notice Get the latest checkpoint at the last checkpointed block
    /// @return The latest checkpoint
    function latestCheckpoint() external view returns (Checkpoint memory);

    /// @notice Get the clearing price at the last checkpointed block
    /// @return The current clearing price
    function clearingPrice() external view returns (uint256);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev This may be less than the balance of this contract as tokens are sold at different prices
    /// @return The total amount of currency raised
    function currencyRaised() external view returns (uint128);

    /// @notice Get the number of the last checkpointed block
    /// @return The block number of the last checkpoint
    function lastCheckpointedBlock() external view returns (uint64);

    /// @notice Get a checkpoint at a block number
    function checkpoints(uint64 blockNumber) external view returns (Checkpoint memory);
}
