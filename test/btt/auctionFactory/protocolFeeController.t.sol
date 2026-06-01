// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from '../BttBase.sol';

import {ContinuousClearingAuctionFactory} from 'src/ContinuousClearingAuctionFactory.sol';

contract ProtocolFeeControllerTest is BttBase {
    function test_WhenProtocolFeeControllerIsSetAtConstruction(address _protocolFeeController) external {
        // it exposes the controller through protocolFeeController()
        // it does not expose a duplicate PROTOCOL_FEE_CONTROLLER() getter

        ContinuousClearingAuctionFactory factory = new ContinuousClearingAuctionFactory(_protocolFeeController);

        assertEq(address(factory.protocolFeeController()), _protocolFeeController);

        (bool success,) = address(factory).staticcall(abi.encodeWithSignature('PROTOCOL_FEE_CONTROLLER()'));
        assertFalse(success);
    }
}
