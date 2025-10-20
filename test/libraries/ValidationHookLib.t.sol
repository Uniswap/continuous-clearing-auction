// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ValidationHookLib} from '../../src/libraries/ValidationHookLib.sol';
import {MockRevertingValidationHook} from '../utils/MockRevertingValidationHook.sol';
import {MockRevertingValidationHookWithCustomError} from '../utils/MockRevertingValidationHook.sol';
import {MockRevertingValidationHookCustomErrorWithString} from '../utils/MockRevertingValidationHook.sol';
import {MockRevertingValidationHookErrorWithString} from '../utils/MockRevertingValidationHook.sol';
import {MockValidationHook} from '../utils/MockValidationHook.sol';
import {MockValidationHookLib} from '../utils/MockValidationHookLib.sol';
import {Test} from 'forge-std/Test.sol';

contract ValidationHookLibTest is Test {
    MockValidationHookLib validationHookLib;
    MockValidationHook validationHook;
    MockRevertingValidationHook revertingValidationHook;
    MockRevertingValidationHookWithCustomError revertingValidationHookWithCustomError;
    MockRevertingValidationHookCustomErrorWithString revertingValidationHookWithString;
    MockRevertingValidationHookErrorWithString revertingValidationHookWithErrorWithString;

    function setUp() public {
        validationHookLib = new MockValidationHookLib();
        validationHook = new MockValidationHook();
        revertingValidationHook = new MockRevertingValidationHook();
        revertingValidationHookWithCustomError = new MockRevertingValidationHookWithCustomError();
        revertingValidationHookWithString = new MockRevertingValidationHookCustomErrorWithString();
        revertingValidationHookWithErrorWithString = new MockRevertingValidationHookErrorWithString();
    }

    function test_handleValidate_withValidationHook_doesNotRevert() public {
        validationHookLib.handleValidate(validationHook, 1, 1, address(0), address(0), bytes(''));
    }

    function test_handleValidate_withRevertingValidationHook_reverts() public {
        vm.expectRevert();
        validationHookLib.handleValidate(revertingValidationHook, 1, 1, address(0), address(0), bytes(''));
    }

    function test_handleValidate_withRevertingValidationHookWithCustomError_reverts() public {
        bytes memory revertData = abi.encodeWithSelector(
            ValidationHookLib.ValidationHookCallFailed.selector,
            abi.encodeWithSelector(MockRevertingValidationHookWithCustomError.CustomError.selector)
        );
        vm.expectRevert(revertData);
        validationHookLib.handleValidate(
            revertingValidationHookWithCustomError, 1, 1, address(0), address(0), bytes('')
        );
    }

    function test_handleValidate_withRevertingValidationHookWithString_reverts() public {
        bytes memory revertData = abi.encodeWithSelector(
            ValidationHookLib.ValidationHookCallFailed.selector,
            abi.encodeWithSelector(MockRevertingValidationHookCustomErrorWithString.StringError.selector, 'reason')
        );
        vm.expectRevert(revertData);
        validationHookLib.handleValidate(revertingValidationHookWithString, 1, 1, address(0), address(0), bytes(''));
    }

    function test_handleValidate_withRevertingValidationHookWithErrorWithString_reverts() public {
        bytes memory revertData = abi.encodeWithSelector(
            ValidationHookLib.ValidationHookCallFailed.selector,
            // bytes4(keccak256("Error(string)"))
            abi.encodeWithSelector(0x08c379a0, 'reason')
        );
        vm.expectRevert(revertData);
        validationHookLib.handleValidate(
            revertingValidationHookWithErrorWithString, 1, 1, address(0), address(0), bytes('')
        );
    }
}
