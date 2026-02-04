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
    /// @notice Error thrown when the caller is not the setter
    error NotSetter();
    /// @notice Error thrown when hook data is required but not provided
    error HookDataRequired(IValidationHook hook);
    /// @notice Error thrown when an invalid module hook is provided
    error InvalidModuleHook();
    /// @notice Error thrown when a module validation reverts
    error ValidateReverted();

    /// @notice Returns the module for a given ID
    /// @param moduleId The ID of the module
    /// @return The module
    function modules(uint256 moduleId) external view returns (Module memory);

    /// @notice Returns the IDs of all set modules
    /// @return The IDs of all modules
    function moduleIds() external view returns (uint256[] memory);
}
