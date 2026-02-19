// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../IValidationHook.sol';

/// @notice A Module wraps an existing hook with additional configuration
struct Module {
    // __reserved;
    bool hasHookData; // Whether the module requires hook data
    bool allowRevert; // Whether the module can revert
    IValidationHook hook; // The underlying validation hook
}

/// @notice A store of hook data and additional metadata
struct ModuleHookData {
    bool requireSenderIsOwner; // Whether the data requires the sender to be the owner
    bool isReplayable; // Whether the data can be used more than once
    uint64 validUntilBlock; // The block number until which the data is valid
    bytes hookData; // The data to forward to the underlying hook
}

/// @notice Interface for a module validation hook
interface IModularValidationHook is IValidationHook {
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

    /// @notice Simulates the validation hook call and returns the revert reason if it fails
    /// @dev If successful, returns an empty bytes array
    function simulate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
        external
        returns (bytes memory);

    /// @notice Sets the hook data for a module
    /// @dev Note that this will overwrite any existing cached hook data for the user of the module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    /// @param _moduleHookData The hook data to set
    function setHookData(uint256 moduleId, address owner, ModuleHookData calldata _moduleHookData) external;

    /// @notice Deletes the hook data for a module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    function deleteHookData(uint256 moduleId, address owner) external;

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
