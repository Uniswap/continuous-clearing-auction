// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {MockERC1155} from 'lib/solady/test/utils/mocks/MockERC1155.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {BaseERC1155ValidationHook} from 'src/periphery/validationHooks/BaseERC1155ValidationHook.sol';

contract BaseERC1155ValidationHookTest is Test {
    IValidationHook hook;
    MockERC1155 token;

    address owner = makeAddr('owner');
    address sender = makeAddr('sender');

    uint256 TOKEN_ID = 0;

    function _getHook() internal virtual returns (IValidationHook) {
        return IValidationHook(new BaseERC1155ValidationHook(address(token), TOKEN_ID));
    }

    function setUp() public {
        token = new MockERC1155();
        hook = _getHook();
    }

    function test_validate_whenSenderIsNotOwner_reverts(uint256 amount) public {
        vm.assume(amount > 0);
        token.mint(owner, TOKEN_ID, amount, bytes(''));

        vm.expectRevert(BaseERC1155ValidationHook.SenderMustBeOwner.selector);
        hook.validate(0, 0, owner, sender, bytes(''));
    }

    function test_validate_whenSenderIsOwnerAndTokenIsNotOwned_reverts() public {
        assertEq(token.balanceOf(owner, TOKEN_ID), 0);
        vm.expectRevert(abi.encodeWithSelector(BaseERC1155ValidationHook.NotOwnerOfERC1155Token.selector, TOKEN_ID));
        hook.validate(0, 0, owner, owner, bytes(''));
    }

    function test_validate_succeeds(uint256 amount) public {
        vm.assume(amount > 0);
        token.mint(owner, TOKEN_ID, amount, bytes(''));
        hook.validate(0, 0, owner, owner, bytes(''));
    }
}
