// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

interface IValidationHookIntrospection is IValidationHook, IERC165 {}

/// @notice Base contract for validation hooks supporting basic introspection
/// @dev Offchain interfaces and integrators should query `supportsInterface` to fuzz what types of validation are run by the hook
abstract contract ValidationHookIntrospection is IValidationHookIntrospection {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IValidationHook).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }
}
