// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IContinuousClearingAuction} from '../../../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionStateLens} from '../../../src/lens/AuctionStateLens.sol';
import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

contract DeployAuctionStateLensMainnet is Script {
    function run() public returns (address lens) {
        vm.startBroadcast();

        lens = address(new AuctionStateLens{salt: bytes32(0)}());
        console2.log('AuctionStateLens deployed to:', address(lens));
        vm.stopBroadcast();
    }
}
