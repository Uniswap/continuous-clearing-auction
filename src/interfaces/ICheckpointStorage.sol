// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../libraries/CheckpointLib.sol';

interface ICheckpointStorage {
    /// @notice Get the latest checkpoint at the last checkpointed block
    /// @dev This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.
    function latestCheckpoint() external view returns (Checkpoint memory);

    /// @notice Get the clearing price at the last checkpointed block
    /// @dev This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.
    function clearingPrice() external view returns (uint256);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.
    /// @dev This also may be less than the balance of this contract as tokens are sold at different prices.
    function currencyRaised() external view returns (uint256);

    /// @notice Get the number of the last checkpointed block
    /// @dev This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.
    function lastCheckpointedBlock() external view returns (uint64);

    /// @notice Get a checkpoint at a block number
    /// @dev The returned checkpoint may not exist if the block was never checkpointed
    /// @param blockNumber The block number of the checkpoint to get
    /// @return checkpoint The checkpoint at the block number
    function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory);
}
