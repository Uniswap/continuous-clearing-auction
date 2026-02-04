// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../IValidationHook.sol';

struct Module {
    // uint88 __reserved;
    bool hasHookData;
    bool allowRevert;
    IValidationHook hook;
}

struct ModuleHookData {
    bool requireSenderIsOwner;
    bool isReplayable;
    uint64 validUntilBlock;
    bytes hookData;
}

/// @notice Interface for a module validation hook
interface IModuleValidationHook is IValidationHook {
    /// @notice Returns the module for a given ID
    /// @param moduleId The ID of the module
    /// @return The module
    function modules(uint256 moduleId) external view returns (Module memory);

    /// @notice Returns the IDs of all set modules
    /// @return The IDs of all modules
    function moduleIds() external view returns (uint256[] memory);
}
