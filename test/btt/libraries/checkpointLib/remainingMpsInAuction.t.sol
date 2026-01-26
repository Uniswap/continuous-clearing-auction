// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Checkpoint, CheckpointLib} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';

contract RemainingMpsInAuctionTest is BttBase {
    function test_WhenCalledWithCheckpoint(uint24 _cumulativeMps) external {
        // it returns mps - checkpoint.cumulativeMps

        uint24 cumulativeMps = uint24(bound(_cumulativeMps, 0, ConstantsLib.MPS));

        Checkpoint memory checkpoint;
        checkpoint.cumulativeMps = cumulativeMps;

        assertEq(CheckpointLib.remainingMpsInAuction(checkpoint), ConstantsLib.MPS - cumulativeMps);
    }
}
