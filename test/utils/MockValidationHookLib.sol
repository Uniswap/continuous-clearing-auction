// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';
import {ValidationHookLib} from '../../src/libraries/ValidationHookLib.sol';

/// @notice Mock implementation of the library
contract MockValidationHookLib {
    function handleValidate(
        IValidationHook hook,
        uint256 maxPrice,
        uint128 amount,
        address owner,
        address sender,
        bytes calldata hookData
    ) external {
        return ValidationHookLib.handleValidate(hook, maxPrice, amount, owner, sender, hookData);
    }
}
