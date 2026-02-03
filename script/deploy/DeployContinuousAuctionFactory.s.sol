// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

/// @title DeployContinuousAuctionFactoryScript
/// @notice Script to deploy the ContinuousClearingAuctionFactory
/// @dev This will deploy to 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 on most EVM chains
///      with the CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
contract DeployContinuousAuctionFactoryScript is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        vm.startBroadcast();

        bytes32 initCodeHash = keccak256(type(ContinuousClearingAuctionFactory).creationCode);
        console2.logBytes32(initCodeHash);

        // Deploys to: 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5
        bytes32 salt = 0xf0354626131f1f8f0a1f7a3837aa270bdcfc1a9e5c6f9125a6f69ba45e416ce3;
        factory = IContinuousClearingAuctionFactory(address(new ContinuousClearingAuctionFactory{salt: salt}()));

        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
