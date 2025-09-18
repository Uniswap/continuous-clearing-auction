// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {MPSLib, ValueX7} from '../../src/libraries/MPSLib.sol';

abstract contract Assertions {
    using MPSLib for ValueX7;

    function hash(Checkpoint memory _checkpoint) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _checkpoint.clearingPrice,
                _checkpoint.totalCleared,
                _checkpoint.cumulativeMps,
                _checkpoint.mps,
                _checkpoint.prev,
                _checkpoint.next,
                _checkpoint.resolvedDemandAboveClearingPrice,
                _checkpoint.cumulativeMpsPerPrice,
                _checkpoint.cumulativeSupplySoldToClearingPriceX7
            )
        );
    }

    function assertEq(Checkpoint memory a, Checkpoint memory b) internal pure returns (bool) {
        return (hash(a) == hash(b));
    }

    function assertEq(ValueX7 a, ValueX7 b) internal pure returns (bool) {
        return (ValueX7.unwrap(a) == ValueX7.unwrap(b));
    }

    function assertGt(ValueX7 a, ValueX7 b) internal pure returns (bool) {
        return (ValueX7.unwrap(a) > ValueX7.unwrap(b));
    }

    function assertGe(ValueX7 a, ValueX7 b) internal pure returns (bool) {
        return (ValueX7.unwrap(a) >= ValueX7.unwrap(b));
    }

    function assertGe(ValueX7 a, ValueX7 b, string memory err) internal pure returns (bool, string memory) {
        return (ValueX7.unwrap(a) >= ValueX7.unwrap(b), err);
    }

    function assertLt(ValueX7 a, ValueX7 b) internal pure returns (bool) {
        return (ValueX7.unwrap(a) < ValueX7.unwrap(b));
    }

    function assertLe(ValueX7 a, ValueX7 b) internal pure returns (bool) {
        return (ValueX7.unwrap(a) <= ValueX7.unwrap(b));
    }
}
