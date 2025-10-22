// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';

contract MockValidationHook is IValidationHook {
    function validate(uint256 maxPrice, uint256 amount, address owner, address sender, bytes calldata hookData)
        external
        pure {}
}
