// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';

abstract contract Assertions {
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
                _checkpoint.cumulativeSupplySoldToClearingPrice
            )
        );
    }

    function assertEq(Checkpoint memory a, Checkpoint memory b) internal pure returns (bool) {
        return (hash(a) == hash(b));
    }
}
