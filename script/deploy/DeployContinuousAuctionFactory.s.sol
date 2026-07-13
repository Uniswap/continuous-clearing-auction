// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

/// @title DeployContinuousAuctionFactoryScript
/// @notice Script to deploy the ContinuousClearingAuctionFactory
/// @dev This will deploy to 0x00cCa200BF124dBfA848937c553864f4B4CE0632 on most EVM chains
///      with the CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
contract DeployContinuousAuctionFactoryScript is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        address protocolFeeController = vm.envOr('PROTOCOL_FEE_CONTROLLER', address(0));
        vm.startBroadcast();

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(ContinuousClearingAuctionFactory).creationCode, abi.encode(protocolFeeController))
        );
        console2.logBytes32(initCodeHash);

        // Deploys to a deterministic address for the configured protocol fee controller.
        bytes32 salt = 0x0f84ad422f72ecae6c249cacbf685a23f203447ecbaf32e8b94ca0a40ea09828;
        factory = IContinuousClearingAuctionFactory(
            address(new ContinuousClearingAuctionFactory{salt: salt}(protocolFeeController))
        );

        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
