// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

/// @title DeployContinuousAuctionFactoryScript
/// @notice Script to deploy the ContinuousClearingAuctionFactory
/// @dev This will deploy to 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D on most EVM chains
///      with the CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
contract DeployContinuousAuctionFactoryScript is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        vm.startBroadcast();

        bytes32 initCodeHash = keccak256(type(ContinuousClearingAuctionFactory).creationCode);

        // Deploys to: 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D
        bytes32 salt = 0xacc35572ce7ac9f43595102465563ac1fcf2dafe0af4110ebf2edb762a5b8c8c;
        factory = IContinuousClearingAuctionFactory(address(new ContinuousClearingAuctionFactory{salt: salt}()));

        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
