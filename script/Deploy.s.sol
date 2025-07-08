// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import 'forge-std/Script.sol';

import {ICounter} from '../src/interfaces/ICounter.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (ICounter counter) {
        uint256 initialNumber = 5;
        bytes memory bytecode = abi.encodePacked(vm.getCode('Counter.sol:Counter'), abi.encode(initialNumber));
        assembly {
            counter := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}
