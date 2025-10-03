// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';
import {StdHelpers} from './utils/StdHelpers.sol';
import {Test} from 'forge-std/Test.sol';

contract StdHelpersTest is StdHelpers, Test {
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

    function test_assertValueX7X7(uint256 a, uint256 b) public pure {
        if (a == b) {
            assertEq(ValueX7X7.wrap(a), ValueX7X7.wrap(b));
            assertGe(ValueX7X7.wrap(a), ValueX7X7.wrap(b));
            assertLe(ValueX7X7.wrap(a), ValueX7X7.wrap(b));
        } else if (a > b) {
            assertGt(ValueX7X7.wrap(a), ValueX7X7.wrap(b));
        } else if (a < b) {
            assertLt(ValueX7X7.wrap(a), ValueX7X7.wrap(b));
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
