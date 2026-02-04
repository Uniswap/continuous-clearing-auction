// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IModuleValidationHook, Module, ModuleHookData} from '../../interfaces/periphery/IModuleValidationHook.sol';
import {EnumerableSetLib} from 'solady/utils/EnumerableSetLib.sol';
import {CustomRevert} from 'v4-core/libraries/CustomRevert.sol';

/// @notice Helper library for converting a Module to its uint256 representation
library ValidationModuleLib {
    /// @notice Converts a Module struct to its uint256 representation
    function toId(Module memory module) internal pure returns (uint256) {
        uint256 id = uint256(uint160(address(module.hook)));
        if (module.hasHookData) {
            id |= 1 << 160;
        }
        if (module.allowRevert) {
            id |= 1 << 161;
        }
        return id;
    }
}

/// @notice Validation hook implementation allowing for multiple modules to be setup at construction
/// @dev Modules wrap a ValidationHook with additional configuration like requiring hookData or allowing reverts
///      this enables projects to add parallel, independent validation checks without complex inheritance
contract ModuleValidationHook is IModuleValidationHook {
    using ValidationModuleLib for Module;
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    mapping(uint256 => Module) private $modules;
    EnumerableSetLib.Uint256Set private $moduleIds;
    mapping(uint256 => mapping(address => ModuleHookData)) private $moduleHookData;

    address public setter;

    constructor(Module[] memory _modules, address _setter) {
        for (uint256 i = 0; i < _modules.length; i++) {
            uint256 id = _modules[i].toId();
            if (address(_modules[i].hook) == address(0)) revert InvalidModuleHook();
            $modules[id] = _modules[i];
            $moduleIds.add(id);
        }
        setter = _setter;
    }

    /// @notice Modifier to only allow the immutable setter to call the function
    modifier onlySetter(address sender) {
        if (sender != setter) revert NotSetter();
        _;
    }

    /// @notice Calls a module and bubbles up the revert reason
    function _callModule(
        Module memory module,
        uint256 maxPrice,
        uint128 amount,
        address owner,
        address sender,
        bytes memory _hookData
    ) internal {
        (bool success, bytes memory reason) = address(module.hook)
            .call(abi.encodeWithSelector(module.hook.validate.selector, maxPrice, amount, owner, sender, _hookData));
        if (!success && !module.allowRevert) {
            // Bubble up custom reverts
            CustomRevert.bubbleUpAndRevertWith(
                address(module.hook), module.hook.validate.selector, ValidateReverted.selector
            );
        }
    }

    /// @notice Loads the cached hook data for a module, returns empty bytes on failure cases
    /// @param moduleId The ID of the module
    /// @param owner The owner passed from the caller of validate
    /// @param sender The sender passed from the caller of validate
    /// @return The cached hook data, if set
    function _loadCachedModuleHookData(uint256 moduleId, address owner, address sender)
        internal
        returns (bytes memory)
    {
        ModuleHookData memory cachedHookData = $moduleHookData[moduleId][owner];
        if (cachedHookData.requireSenderIsOwner && sender != owner) {
            return bytes('');
        } else if (cachedHookData.validUntilBlock < block.number) {
            delete $moduleHookData[moduleId][owner];
            return bytes('');
        } else {
            return cachedHookData.hookData;
        }
    }

    /// @notice Sets the hook data for a module
    /// @dev Note that this will overwrite any existing cached hook data for the user of the module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    /// @param _moduleHookData The hook data to set
    function setHookData(uint256 moduleId, address owner, ModuleHookData calldata _moduleHookData)
        external
        onlySetter(msg.sender)
    {
        $moduleHookData[moduleId][owner] = _moduleHookData;
    }

    /// @notice Deletes the hook data for a module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    function deleteHookData(uint256 moduleId, address owner) external onlySetter(msg.sender) {
        delete $moduleHookData[moduleId][owner];
    }

    /// @inheritdoc IValidationHook
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData) public {
        bytes[] memory providedHookData = abi.decode(hookData, (bytes[]));
        uint256[] memory _moduleIds = $moduleIds.values();

        // Iterate over all set module IDs. The number of modules requiring hookData should be limited as this is O(n*m).
        for (uint256 i = 0; i < _moduleIds.length; i++) {
            uint256 id = _moduleIds[i];
            Module memory module = $modules[id];
            bytes memory _hookData;
            if (module.hasHookData) {
                // Find either the provided hookData or any hookData in storage
                uint256 _id;
                for (uint256 j = 0; j < providedHookData.length; j++) {
                    (_id, _hookData) = abi.decode(providedHookData[j], (uint256, bytes));
                    if (_id == id) {
                        break;
                    }
                }
                // If no hookData was provided, check the cache for hookData
                if (_hookData.length == 0) {
                    _hookData = _loadCachedModuleHookData(id, owner, sender);
                }

                if (_hookData.length == 0) {
                    revert HookDataRequired(module.hook);
                }
            }

            _callModule(module, maxPrice, amount, owner, sender, _hookData);
        }
    }

    /// @notice Simulates the validation hook call and returns the revert reason if it fails
    /// @dev If successful, returns an empty bytes array
    function simulate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
        external
        returns (bytes memory)
    {
        try this.validate(maxPrice, amount, owner, sender, hookData) {}
        catch (bytes memory reason) {
            return reason;
        }
        return bytes('');
    }

    // Getters
    function modules(uint256 moduleId) external view returns (Module memory) {
        return $modules[moduleId];
    }

    function moduleIds() external view returns (uint256[] memory) {
        return $moduleIds.values();
    }
}
