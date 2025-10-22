// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';

import {MockPermitSingleForwarder} from 'btt/mocks/MockPermitSingleForwarder.sol';
import {IAllowanceTransfer} from 'twap-auction/PermitSingleForwarder.sol';

contract PermitTest is BttBase {
    bytes4 internal PERMIT_SELECTOR = 0x2b67b570;

    function setUp() public {}

    function test_WhenValueGT0(
        string memory _permit2,
        address _owner,
        IAllowanceTransfer.PermitSingle memory _permitSingle,
        bytes calldata _signature,
        uint128 _value
    ) external {
        // it reverts

        // TODO: @todo Fix as part of #204 - https://github.com/Uniswap/twap-auction/issues/204
        return;

        address permit2 = makeAddr(_permit2);

        MockPermitSingleForwarder forwarder = new MockPermitSingleForwarder(IAllowanceTransfer(permit2));

        uint256 value = bound(_value, 1, type(uint128).max);
        vm.deal(address(this), value);

        vm.mockCall(permit2, PERMIT_SELECTOR, bytes(''));

        vm.expectRevert();
        forwarder.permit{value: value}(_owner, _permitSingle, _signature);
    }

    modifier whenValueEQ0() {
        _;
    }

    function test_WhenPermit2Reverts(
        string memory _permit2,
        address _owner,
        IAllowanceTransfer.PermitSingle memory _permitSingle,
        bytes calldata _signature,
        bytes memory _revertData
    ) external whenValueEQ0 {
        // it returns the error

        address permit2 = makeAddr(_permit2);

        MockPermitSingleForwarder forwarder = new MockPermitSingleForwarder(IAllowanceTransfer(permit2));

        // When no code at _permit2, it will revert and not be caught by the try catch.
        vm.assume(permit2.code.length == 0);
        vm.expectRevert();
        forwarder.permit(_owner, _permitSingle, _signature);

        vm.mockCallRevert(permit2, PERMIT_SELECTOR, _revertData);
        assertEq(forwarder.permit(_owner, _permitSingle, _signature), _revertData);
    }

    function test_WhenPermit2DoesNotReverts(
        string memory _permit2,
        address _owner,
        IAllowanceTransfer.PermitSingle memory _permitSingle,
        bytes calldata _signature
    ) external whenValueEQ0 {
        // it returns empty bytes

        address permit2 = makeAddr(_permit2);

        MockPermitSingleForwarder forwarder = new MockPermitSingleForwarder(IAllowanceTransfer(permit2));

        vm.mockCall(permit2, PERMIT_SELECTOR, bytes(''));
        bytes memory result = forwarder.permit(_owner, _permitSingle, _signature);
        emit log_bytes(result);

        assertEq(result.length, 0);
    }
}
