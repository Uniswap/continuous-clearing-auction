// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';

import {MockPermitSingleForwarder} from 'btt/mocks/MockPermitSingleForwarder.sol';
import {IAllowanceTransfer} from 'twap-auction/PermitSingleForwarder.sol';

contract ConstructorTest is BttBase {
    function test_WhenCalledWithPermit2(address _permit2) external {
        // it writes permit2

        vm.assume(_permit2 != address(0));

        MockPermitSingleForwarder forwarder = new MockPermitSingleForwarder(IAllowanceTransfer(address(_permit2)));

        assertEq(address(forwarder.permit2()), address(_permit2));
    }
}
