// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {StdAssertions} from 'forge-std/StdAssertions.sol';

abstract contract Assertions is StdAssertions {
    using ValueX7Lib for ValueX7;

    function hash(Checkpoint memory _checkpoint) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _checkpoint.clearingPrice,
                _checkpoint.cumulativeMps,
                _checkpoint.prev,
                _checkpoint.next,
                _checkpoint.cumulativeMpsPerPrice,
                _checkpoint.currencyRaisedAtClearingPriceQ96_X7
            )
        );
    }

    function assertEq(Checkpoint memory a, Checkpoint memory b) internal pure {
        assertEq(hash(a), hash(b));
    }

    function assertNotEq(Checkpoint memory a, Checkpoint memory b) internal pure {
        assertNotEq(hash(a), hash(b));
    }

    function assertEq(ValueX7 a, ValueX7 b) internal pure {
        assertEq(ValueX7.unwrap(a), ValueX7.unwrap(b));
    }

    function assertEq(ValueX7 a, ValueX7 b, string memory err) internal pure {
        assertEq(ValueX7.unwrap(a), ValueX7.unwrap(b), err);
    }

    function assertGt(ValueX7 a, ValueX7 b) internal pure {
        assertGt(ValueX7.unwrap(a), ValueX7.unwrap(b));
    }

    function assertGe(ValueX7 a, ValueX7 b) internal pure {
        assertGe(ValueX7.unwrap(a), ValueX7.unwrap(b));
    }

    function assertGe(ValueX7 a, ValueX7 b, string memory err) internal pure {
        assertGe(ValueX7.unwrap(a), ValueX7.unwrap(b), err);
    }

    function assertLt(ValueX7 a, ValueX7 b) internal pure {
        assertLt(ValueX7.unwrap(a), ValueX7.unwrap(b));
    }

    function assertLe(ValueX7 a, ValueX7 b) internal pure {
        assertLe(ValueX7.unwrap(a), ValueX7.unwrap(b));
    }
}
