// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

/// @title DeployContinuousAuctionFactoryScript
/// @notice Script to deploy the ContinuousClearingAuctionFactory
/// @dev This will deploy to 0xcca1101C61cF5cb44C968947985300DF945C3565 on most EVM chains
///      with the CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
contract DeployContinuousAuctionFactoryScript is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        vm.startBroadcast();

        bytes32 initCodeHash = keccak256(type(ContinuousClearingAuctionFactory).creationCode);
        console2.logBytes32(initCodeHash);

        // Deploys to: 0xcca1101C61cF5cb44C968947985300DF945C3565
        bytes32 salt = 0x3607090e08af583d30437fc9eb4cd2105a732f30be11624f8d145b53167f17f9;
        factory = IContinuousClearingAuctionFactory(address(new ContinuousClearingAuctionFactory{salt: salt}()));

        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
