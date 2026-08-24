// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BttBase} from 'btt/BttBase.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {
    IMaxBidPriceValidationHook,
    MaxBidPriceValidationHook
} from 'src/periphery/validationHooks/MaxBidPriceValidationHook.sol';

contract MaxBidPriceValidationHookTest is BttBase {
    function test_Constructor(uint256 _maxBidPrice) external {
        // it sets maxBidPrice

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);
        assertEq(hook.maxBidPrice(), _maxBidPrice);
    }

    function test_WhenMaxBidPriceIsZero(
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external {
        // it does not revert

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(0);
        hook.validate(_maxPrice, _amount, _owner, _sender, _hookData);
    }

    modifier whenMaxBidPriceIsNotZero() {
        _;
    }

    function test_WhenMaxPriceGTMaxBidPrice(
        uint256 _maxBidPrice,
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external whenMaxBidPriceIsNotZero {
        // it reverts with {MaxBidPriceExceeded}

        _maxBidPrice = bound(_maxBidPrice, 1, type(uint256).max - 1);
        _maxPrice = bound(_maxPrice, _maxBidPrice + 1, type(uint256).max);

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);

        vm.expectRevert(MaxBidPriceValidationHook.MaxBidPriceExceeded.selector);
        hook.validate(_maxPrice, _amount, _owner, _sender, _hookData);
    }

    modifier whenMaxPriceLTEMaxBidPrice() {
        _;
    }

    function test_WhenMaxPriceEQMaxBidPrice(
        uint256 _maxBidPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external whenMaxBidPriceIsNotZero whenMaxPriceLTEMaxBidPrice {
        // it does not revert

        _maxBidPrice = bound(_maxBidPrice, 1, type(uint256).max);

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);
        hook.validate(_maxBidPrice, _amount, _owner, _sender, _hookData);
    }

    function test_WhenMaxPriceLTMaxBidPrice(
        uint256 _maxBidPrice,
        uint256 _maxPrice,
        uint128 _amount,
        address _owner,
        address _sender,
        bytes calldata _hookData
    ) external whenMaxBidPriceIsNotZero whenMaxPriceLTEMaxBidPrice {
        // it does not revert

        _maxBidPrice = bound(_maxBidPrice, 1, type(uint256).max);
        _maxPrice = bound(_maxPrice, 0, _maxBidPrice - 1);

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);
        hook.validate(_maxPrice, _amount, _owner, _sender, _hookData);
    }

    function test_WhenInterfaceIsSupported(uint256 _maxBidPrice) external {
        // it returns true

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);

        assertTrue(hook.supportsInterface(type(IERC165).interfaceId));
        assertTrue(hook.supportsInterface(type(IValidationHook).interfaceId));
        assertTrue(hook.supportsInterface(type(IMaxBidPriceValidationHook).interfaceId));
    }

    function test_WhenInterfaceIsNotSupported(uint256 _maxBidPrice, bytes4 _interfaceId) external {
        // it returns false

        vm.assume(
            _interfaceId != type(IERC165).interfaceId && _interfaceId != type(IValidationHook).interfaceId
                && _interfaceId != type(IMaxBidPriceValidationHook).interfaceId
        );

        MaxBidPriceValidationHook hook = new MaxBidPriceValidationHook(_maxBidPrice);
        assertFalse(hook.supportsInterface(_interfaceId));
    }
}
