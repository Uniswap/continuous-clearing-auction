// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {Demand} from '../../src/libraries/DemandLib.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../../src/libraries/ValueX7X7Lib.sol';
import {StdAssertions} from 'forge-std/StdAssertions.sol';

abstract contract Assertions is StdAssertions {
    using ValueX7Lib for ValueX7;

    function hash(Checkpoint memory _checkpoint) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _checkpoint.clearingPrice,
                _checkpoint.totalClearedX7X7,
                _checkpoint.cumulativeMps,
                _checkpoint.mps,
                _checkpoint.prev,
                _checkpoint.next,
                keccak256(abi.encode(_checkpoint.sumDemandAboveClearingPrice)),
                _checkpoint.cumulativeMpsPerPrice,
                _checkpoint.cumulativeSupplySoldToClearingPriceX7X7
            )
        );
    }

    function hash(Demand memory _demand) internal pure returns (bytes32) {
        return keccak256(abi.encode(_demand.currencyDemandX7, _demand.tokenDemandX7));
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

    function assertEq(ValueX7X7 a, ValueX7X7 b) internal pure {
        assertEq(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b));
    }

    function assertGt(ValueX7X7 a, ValueX7X7 b) internal pure {
        assertGt(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b));
    }

    function assertGe(ValueX7X7 a, ValueX7X7 b) internal pure {
        assertGe(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b));
    }

    function assertLt(ValueX7X7 a, ValueX7X7 b) internal pure {
        assertLt(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b));
    }

    function assertLe(ValueX7X7 a, ValueX7X7 b) internal pure {
        assertLe(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b));
    }

    function assertEq(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure {
        assertEq(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), err);
    }

    function assertGt(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure {
        assertGt(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), err);
    }

    function assertGe(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure {
        assertGe(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), err);
    }

    function assertLt(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure {
        assertLt(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), err);
    }

    function assertLe(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure {
        assertLe(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), err);
    }

    function assertEq(Demand memory a, Demand memory b) internal pure {
        assertEq(hash(a), hash(b));
    }

    function assertNotEq(Demand memory a, Demand memory b) internal pure {
        assertNotEq(hash(a), hash(b));
    }

    function assertEq(Demand memory a, Demand memory b, string memory err) internal pure {
        assertEq(hash(a), hash(b), err);
    }

    function assertNotEq(Demand memory a, Demand memory b, string memory err) internal pure {
        assertNotEq(hash(a), hash(b), err);
    }
}
