// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseERC1155ValidationHookTest} from './BaseERC1155ValidationHook.t.sol';
import {Test} from 'forge-std/Test.sol';
import {
    GatedERC1155ValidationHook,
    IGatedERC1155ValidationHook
} from 'src/periphery/validationHooks/GatedERC1155ValidationHook.sol';
import {IValidationHookIntrospection} from 'src/periphery/validationHooks/ValidationHookIntrospection.sol';

contract GatedERC1155ValidationHookTest is BaseERC1155ValidationHookTest {
    function _getHook() internal override returns (IValidationHookIntrospection) {
        // Default behavior for full backwards test compatibility
        return IValidationHookIntrospection(new GatedERC1155ValidationHook(address(token), TOKEN_ID, type(uint256).max));
    }

    // customizable getter for hook configuration
    function _getHook(uint256 _gateUntil) internal returns (IValidationHookIntrospection) {
        return IValidationHookIntrospection(new GatedERC1155ValidationHook(address(token), TOKEN_ID, _gateUntil));
    }

    function test_supportsInterface() public view override {
        super.test_supportsInterface();
        assertEq(hook.supportsInterface(type(IGatedERC1155ValidationHook).interfaceId), true);
    }

    modifier givenGateUntilIsLessThanCurrentBlock() {
        _;
    }

    function test_validate_whenSenderIsNotOwner_reverts(uint64 _gateUntil, uint256 amount)
        public
        givenGateUntilIsLessThanCurrentBlock
    {
        vm.assume(_gateUntil > 0);
        hook = _getHook(_gateUntil);
        vm.roll(_gateUntil - 1);
        test_validate_whenSenderIsNotOwner_reverts(amount);
    }

    function test_validate_whenSenderIsOwnerAndTokenIsNotOwned_reverts(uint64 _gateUntil)
        public
        givenGateUntilIsLessThanCurrentBlock
    {
        vm.assume(_gateUntil > 0);
        hook = _getHook(_gateUntil);
        vm.roll(_gateUntil - 1);
        test_validate_whenSenderIsOwnerAndTokenIsNotOwned_reverts();
    }

    modifier givenGateUntilIsGTECurrentBlock() {
        _;
    }

    function test_validate_whenSenderIsNotOwnerAndGateUntilIsGTECurrentBlock(uint64 _gateUntil, uint256 amount)
        public
        givenGateUntilIsGTECurrentBlock
    {
        // it does not revert

        _gateUntil = uint64(_bound(_gateUntil, block.number, type(uint64).max));
        hook = _getHook(_gateUntil);

        vm.roll(_gateUntil);

        assertNotEq(sender, owner);
        token.mint(owner, TOKEN_ID, amount, bytes(''));

        hook.validate(0, 0, owner, sender, bytes(''));
    }

    function test_validate_whenSenderIsOwnerAndTokenIsNotOwnedAndGateUntilIsGTECurrentBlock(uint64 _gateUntil)
        public
        givenGateUntilIsGTECurrentBlock
    {
        _gateUntil = uint64(_bound(_gateUntil, block.number, type(uint64).max));
        hook = _getHook(_gateUntil);

        vm.roll(_gateUntil);

        assertEq(token.balanceOf(owner, TOKEN_ID), 0);
        hook.validate(0, 0, owner, owner, bytes(''));
    }
}
