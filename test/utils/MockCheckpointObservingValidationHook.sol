// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';

interface ILastCheckpointedBlock {
    function lastCheckpointedBlock() external view returns (uint64);
}

/// @notice Mock validation hook that records auction checkpoint state during validation
contract MockCheckpointObservingValidationHook is IValidationHook {
    uint64 public observedLastCheckpointedBlock;

    function validate(uint256, uint128, address, address, bytes calldata) external override {
        observedLastCheckpointedBlock = ILastCheckpointedBlock(msg.sender).lastCheckpointedBlock();
    }
}
