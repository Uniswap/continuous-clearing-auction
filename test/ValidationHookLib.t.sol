// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ValidationHookLib} from '../src/libraries/ValidationHookLib.sol';
import {MockRevertingValidationHook} from './utils/MockRevertingValidationHook.sol';
import {MockRevertingValidationHookWithCustomError} from './utils/MockRevertingValidationHook.sol';
import {MockRevertingValidationHookWithString} from './utils/MockRevertingValidationHook.sol';

import {MockValidationHook} from './utils/MockValidationHook.sol';
import {MockValidationHookLib} from './utils/MockValidationHookLib.sol';
import {Test} from 'forge-std/Test.sol';

contract ValidationHookLibTest is Test {
    MockValidationHookLib validationHookLib;
    MockValidationHook validationHook;
    MockRevertingValidationHook revertingValidationHook;
    MockRevertingValidationHookWithCustomError revertingValidationHookWithCustomError;
    MockRevertingValidationHookWithString revertingValidationHookWithString;

    function setUp() public {
        validationHookLib = new MockValidationHookLib();
        validationHook = new MockValidationHook();
        revertingValidationHook = new MockRevertingValidationHook();
        revertingValidationHookWithCustomError = new MockRevertingValidationHookWithCustomError();
        revertingValidationHookWithString = new MockRevertingValidationHookWithString();
    }

    function test_handleValidate_withValidationHook_doesNotRevert() public {
        validationHookLib.handleValidate(validationHook, 1, true, 1, address(0), address(0), bytes(''));
    }

    function test_handleValidate_withRevertingValidationHook_reverts() public {
        vm.expectRevert();
        validationHookLib.handleValidate(revertingValidationHook, 1, true, 1, address(0), address(0), bytes(''));
    }

    function test_handleValidate_withRevertingValidationHookWithCustomError_reverts() public {
        bytes memory revertData = abi.encodeWithSelector(
            ValidationHookLib.ValidationHookCallFailed.selector,
            abi.encodeWithSelector(MockRevertingValidationHookWithCustomError.CustomError.selector)
        );
        vm.expectRevert(revertData);
        validationHookLib.handleValidate(
            revertingValidationHookWithCustomError, 1, true, 1, address(0), address(0), bytes('')
        );
    }

    function test_handleValidate_withRevertingValidationHookWithString_reverts() public {
        bytes memory revertData = abi.encodeWithSelector(
            ValidationHookLib.ValidationHookCallFailed.selector,
            abi.encodeWithSelector(MockRevertingValidationHookWithString.StringError.selector, 'reason')
        );
        vm.expectRevert(revertData);
        validationHookLib.handleValidate(
            revertingValidationHookWithString, 1, true, 1, address(0), address(0), bytes('')
        );
    }
}
