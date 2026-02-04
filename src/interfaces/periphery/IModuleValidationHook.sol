// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../IValidationHook.sol';

struct Module {
    // __reserved;
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
    /// @notice Error thrown when a module is already set
    error ModuleAlreadySet(uint256 moduleId);
    /// @notice Error thrown when the caller is not the setter
    error NotSetter();
    /// @notice Error thrown when hook data is required but not provided
    error HookDataRequired(IValidationHook hook);
    /// @notice Error thrown when an invalid owner is provided
    error InvalidOwner();
    /// @notice Error thrown when an invalid valid until block is provided
    error InvalidValidUntilBlock(uint64 validUntilBlock, uint256 currentBlock);
    /// @notice Error thrown when an invalid module hook is provided
    error InvalidModuleHook();
    /// @notice Error thrown when a module validation reverts
    error ValidateReverted();

    /// @notice Emitted when a module is set
    event ModuleSet(uint256 indexed moduleId, IValidationHook hook, bool hasHookData, bool allowRevert);

    /// @notice Emitted when hook data is set for a module
    event HookDataSet(uint256 indexed moduleId, address indexed owner, uint64 validUntilBlock, bytes hookData);
    /// @notice Emitted when hook data is deleted for a module
    event HookDataDeleted(uint256 indexed moduleId, address indexed owner);

    /// @notice Returns the module for a given ID
    /// @param moduleId The ID of the module
    /// @return The module
    function modules(uint256 moduleId) external view returns (Module memory);

    /// @notice Returns the IDs of all set modules
    /// @return The IDs of all modules
    function moduleIds() external view returns (uint256[] memory);

    /// @notice Returns the hook data for a module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    /// @return The hook data
    function moduleHookData(uint256 moduleId, address owner) external view returns (ModuleHookData memory);
}
