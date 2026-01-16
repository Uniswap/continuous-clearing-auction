// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

/// @title DeployContinuousAuctionFactoryScript
/// @notice Script to deploy the ContinuousClearingAuctionFactory
/// @dev This will deploy to 0xcca110c1136B93Eb113cceae3C25e52E180B32C9 on most EVM chains
///      with the CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
contract DeployContinuousAuctionFactoryScript is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        vm.startBroadcast();

        // For the commit hash b618287ea31de52973d26305427a75971096a746, the init code hash is 0xb5c4609788dadcd1404ef748f96e85addb44bb5c14a41e40b1bd889d9dc425aa
        bytes32 initCodeHash = keccak256(type(ContinuousClearingAuctionFactory).creationCode);
        console2.logBytes32(initCodeHash);

        // Deploys to: 0xcca110c1136B93Eb113cceae3C25e52E180B32C9
        bytes32 salt = 0x0e011dcbb712b35d14266d8de5f6139e81e3ea7d0c07d10ce418a027535889be;
        factory = IContinuousClearingAuctionFactory(address(new ContinuousClearingAuctionFactory{salt: salt}()));

        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
