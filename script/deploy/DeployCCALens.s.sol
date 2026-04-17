// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CCALens} from '../../src/lens/CCALens.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

contract DeployCCALensScript is Script {
    function run() public returns (address lens) {
        vm.startBroadcast();

        lens = address(new CCALens{salt: bytes32(0)}());
        console2.log('CCALens deployed to:', address(lens));
        vm.stopBroadcast();
    }
}
