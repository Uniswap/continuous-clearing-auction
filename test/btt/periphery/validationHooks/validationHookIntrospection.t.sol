// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BttBase} from 'btt/BttBase.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {ValidationHookIntrospection} from 'src/periphery/validationHooks/ValidationHookIntrospection.sol';

contract MockValidationHookIntrospection is ValidationHookIntrospection {
    function validate(uint256, uint128, address, address, bytes calldata) external pure {}
}

contract ValidationHookIntrospectionTest is BttBase {
    function test_SupportsInterface() external {
        // it supports IERC165
        // it supports IValidationHook
        // it does not expose supportsMode(bytes32)

        MockValidationHookIntrospection hook = new MockValidationHookIntrospection();

        assertTrue(hook.supportsInterface(type(IERC165).interfaceId));
        assertTrue(hook.supportsInterface(type(IValidationHook).interfaceId));

        (bool success,) = address(hook).staticcall(abi.encodeWithSignature('supportsMode(bytes32)', bytes32(0)));
        assertFalse(success);
    }
}
