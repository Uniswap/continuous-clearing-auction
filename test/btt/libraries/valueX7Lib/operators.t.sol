// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ValueX7} from 'continuous-clearing-auction/libraries/ValueX7Lib.sol';

contract ValueX7OperatorsTest is BttBase {
    function test_Add(ValueX7 _a, ValueX7 _b) external pure {
        // it returns the sum of two ValueX7 values

        uint256 a = bound(ValueX7.unwrap(_a), 0, type(uint256).max / 2);
        uint256 b = bound(ValueX7.unwrap(_b), 0, type(uint256).max / 2);

        assertEq(ValueX7.unwrap(ValueX7.wrap(a) + ValueX7.wrap(b)), a + b);
    }

    function test_Sub(ValueX7 _a, ValueX7 _b) external pure {
        // it returns the difference of two ValueX7 values

        uint256 a = ValueX7.unwrap(_a);
        uint256 b = bound(ValueX7.unwrap(_b), 0, a);

        assertEq(ValueX7.unwrap(ValueX7.wrap(a) - ValueX7.wrap(b)), a - b);
    }

    function test_GreaterThanOrEqual(ValueX7 _a, ValueX7 _b) external pure {
        // it compares the unwrapped values

        uint256 a = ValueX7.unwrap(_a);
        uint256 b = ValueX7.unwrap(_b);

        assertEq(ValueX7.wrap(a) >= ValueX7.wrap(b), a >= b);
    }
}
