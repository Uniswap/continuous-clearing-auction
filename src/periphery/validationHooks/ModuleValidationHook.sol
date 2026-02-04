// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IModuleValidationHook, Module, ModuleHookData} from '../../interfaces/periphery/IModuleValidationHook.sol';
import {ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';
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
contract ModuleValidationHook is IModuleValidationHook, ValidationHookIntrospection, BlockNumberish {
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
            bool added = $moduleIds.add(id);
            if (!added) revert ModuleAlreadySet(id);
            emit ModuleSet(id, _modules[i].hook, _modules[i].hasHookData, _modules[i].allowRevert);
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
        (bool success,) = address(module.hook)
            .call(abi.encodeWithSelector(module.hook.validate.selector, maxPrice, amount, owner, sender, _hookData));
        if (!success && !module.allowRevert) {
            // Bubble up all reverts
            CustomRevert.bubbleUpAndRevertWith(
                address(module.hook), module.hook.validate.selector, ValidateReverted.selector
            );
        }
    }

    /// @notice Loads the cached hook data for a module, returns empty bytes on failure cases
    /// @param moduleId The ID of the module
    /// @param owner The owner passed from the caller of validate
    /// @param sender The sender passed from the caller of validate
    function _loadCachedModuleHookData(uint256 moduleId, address owner, address sender)
        internal
        returns (bytes memory hookData)
    {
        ModuleHookData memory cached = $moduleHookData[moduleId][owner];
        if (!cached.requireSenderIsOwner || sender == owner) {
            if (cached.validUntilBlock >= _getBlockNumberish()) {
                hookData = cached.hookData;
                if (!cached.isReplayable) {
                    delete $moduleHookData[moduleId][owner];
                }
            } else {
                delete $moduleHookData[moduleId][owner];
            }
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
        if (owner == address(0)) {
            revert InvalidOwner();
        }
        if (_moduleHookData.validUntilBlock < _getBlockNumberish()) {
            revert InvalidValidUntilBlock(_moduleHookData.validUntilBlock, _getBlockNumberish());
        }
        $moduleHookData[moduleId][owner] = _moduleHookData;
        emit HookDataSet(moduleId, owner, _moduleHookData.validUntilBlock, _moduleHookData.hookData);
    }

    /// @notice Deletes the hook data for a module
    /// @param moduleId The ID of the module
    /// @param owner The owner of the hook data
    function deleteHookData(uint256 moduleId, address owner) external onlySetter(msg.sender) {
        delete $moduleHookData[moduleId][owner];
        emit HookDataDeleted(moduleId, owner);
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
                    bytes memory temp;
                    (_id, temp) = abi.decode(providedHookData[j], (uint256, bytes));
                    if (_id == id) {
                        _hookData = temp;
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
    {
        try this.validate(maxPrice, amount, owner, sender, hookData) {
            assembly {
                revert(0, 0)
            }
        } catch (bytes memory reason) {
            assembly {
                revert(add(reason, 32), mload(reason))
            }
        }
    }

    // ERC-165 support
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IModuleValidationHook).interfaceId;
    }

    // Getters
    /// @inheritdoc IModuleValidationHook
    function modules(uint256 moduleId) external view returns (Module memory) {
        return $modules[moduleId];
    }

    /// @inheritdoc IModuleValidationHook
    function moduleIds() external view returns (uint256[] memory) {
        return $moduleIds.values();
    }

    /// @inheritdoc IModuleValidationHook
    function moduleHookData(uint256 moduleId, address owner) external view returns (ModuleHookData memory) {
        return $moduleHookData[moduleId][owner];
    }
}
