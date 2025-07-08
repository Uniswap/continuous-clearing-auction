// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICounter} from '../../src/interfaces/ICounter.sol';
import {Test} from 'forge-std/Test.sol';

contract CounterDeployer is Test {
    function deploy(uint256 initialNumber) internal returns (ICounter counter) {
        bytes memory bytecode = abi.encodePacked(vm.getCode('Counter.sol:Counter'), abi.encode(initialNumber));
        assembly {
            counter := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}
