// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {Test} from 'forge-std/Test.sol';

contract AssertionsTest is Assertions, Test {
    function test_assertValueX7(uint256 a, uint256 b) public pure {
        if (a == b) {
            assertEq(ValueX7.wrap(a), ValueX7.wrap(b));
            assertGe(ValueX7.wrap(a), ValueX7.wrap(b));
            assertLe(ValueX7.wrap(a), ValueX7.wrap(b));
        } else if (a > b) {
            assertGt(ValueX7.wrap(a), ValueX7.wrap(b));
        } else if (a < b) {
            assertLt(ValueX7.wrap(a), ValueX7.wrap(b));
        }
    }

    function test_assertCheckpoint(Checkpoint memory a, Checkpoint memory b) public pure {
        if (hash(a) == hash(b)) {
            assertEq(a, b);
        } else {
            assertNotEq(a, b);
        }
    }
}
