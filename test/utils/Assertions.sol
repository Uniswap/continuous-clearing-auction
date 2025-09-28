// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {Demand} from '../../src/libraries/DemandLib.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../../src/libraries/ValueX7X7Lib.sol';

abstract contract Assertions {
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

    function assertEq(ValueX7X7 a, ValueX7X7 b) internal pure returns (bool) {
        return (ValueX7X7.unwrap(a) == ValueX7X7.unwrap(b));
    }

    function assertGt(ValueX7X7 a, ValueX7X7 b) internal pure returns (bool) {
        return (ValueX7X7.unwrap(a) > ValueX7X7.unwrap(b));
    }

    function assertGe(ValueX7X7 a, ValueX7X7 b) internal pure returns (bool) {
        return (ValueX7X7.unwrap(a) >= ValueX7X7.unwrap(b));
    }

    function assertLe(ValueX7X7 a, ValueX7X7 b) internal pure returns (bool) {
        return (ValueX7X7.unwrap(a) <= ValueX7X7.unwrap(b));
    }

    function assertEq(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure returns (bool, string memory) {
        return (ValueX7X7.unwrap(a) == ValueX7X7.unwrap(b), err);
    }

    function assertGt(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure returns (bool, string memory) {
        return (ValueX7X7.unwrap(a) > ValueX7X7.unwrap(b), err);
    }

    function assertGe(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure returns (bool, string memory) {
        return (ValueX7X7.unwrap(a) >= ValueX7X7.unwrap(b), err);
    }

    function assertLe(ValueX7X7 a, ValueX7X7 b, string memory err) internal pure returns (bool, string memory) {
        return (ValueX7X7.unwrap(a) <= ValueX7X7.unwrap(b), err);
    }

    function assertEq(Demand memory a, Demand memory b) internal pure returns (bool) {
        return assertEq(a.currencyDemandX7, b.currencyDemandX7) && assertEq(a.tokenDemandX7, b.tokenDemandX7);
    }

    function assertEq(Demand memory a, Demand memory b, string memory err)
        internal
        pure
        returns (bool, string memory)
    {
        return (assertEq(a.currencyDemandX7, b.currencyDemandX7) && assertEq(a.tokenDemandX7, b.tokenDemandX7), err);
    }
}
