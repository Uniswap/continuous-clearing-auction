// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ContinuousClearingAuctionFactory} from '../../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from '../../../src/interfaces/IContinuousClearingAuctionFactory.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

contract DeployContinuousAuctionFactoryMainnet is Script {
    function run() public returns (IContinuousClearingAuctionFactory factory) {
        vm.startBroadcast();
        factory = IContinuousClearingAuctionFactory(address(new ContinuousClearingAuctionFactory{salt: bytes32(0)}()));
        console2.log('ContinuousClearingAuctionFactory deployed to:', address(factory));
        vm.stopBroadcast();
    }
}
