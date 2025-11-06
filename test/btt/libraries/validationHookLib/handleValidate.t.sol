// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {IValidationHook, ValidationHookLib} from 'continuous-clearing-auction/libraries/ValidationHookLib.sol';

contract ValidationHookWrapper {
    function validate(
        IValidationHook hook,
        uint256 maxPrice,
        uint128 amount,
        address owner,
        address sender,
        bytes calldata hookData
    ) external {
        ValidationHookLib.handleValidate(hook, maxPrice, amount, owner, sender, hookData);
    }
}

contract MockValidationHook is IValidationHook {
    error RevertError();

    bool public willRevert;

    constructor(bool _willRevert) {
        willRevert = _willRevert;
    }

    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
        external
    {
        if (willRevert) {
            revert RevertError();
        }
    }
}

contract HandleValidateTest is BttBase {
    ValidationHookWrapper public validationHookWrapper;

    function setUp() external {
        validationHookWrapper = new ValidationHookWrapper();
    }

    function test_WhenHookIsAddressZero(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external {
        // it returns early
        vm.record();
        ValidationHookLib.handleValidate(IValidationHook(address(0)), _maxPrice, _amount, _owner, _sender, _hookData);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(validationHookWrapper));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    modifier whenHookIsNotAddressZero() {
        _;
    }

    function test_WhenTheHookCallFails(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external whenHookIsNotAddressZero {
        // it reverts with {ValidationHookCallFailed}

        MockValidationHook _hook =
            new MockValidationHook{salt: keccak256(abi.encode(_maxPrice, _amount, _owner, _sender, _hookData))}(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidationHookLib.ValidationHookCallFailed.selector,
                abi.encodeWithSelector(MockValidationHook.RevertError.selector)
            )
        );
        validationHookWrapper.validate(_hook, _maxPrice, _amount, _owner, _sender, _hookData);
    }

    function test_WhenTheHookCallSucceeds(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external whenHookIsNotAddressZero {
        // it returns

        MockValidationHook _hook =
            new MockValidationHook{salt: keccak256(abi.encode(_maxPrice, _amount, _owner, _sender, _hookData))}(false);
        validationHookWrapper.validate(_hook, _maxPrice, _amount, _owner, _sender, _hookData);
    }
}
