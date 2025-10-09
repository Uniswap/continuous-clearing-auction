// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Checkpoint, CheckpointLib} from 'twap-auction/libraries/CheckpointLib.sol';
import {ValueX7X7} from 'twap-auction/libraries/ValueX7X7Lib.sol';

contract GetCurrencyRaisedTest is BttBase {
    function test_WhenCalledWithCheckpoint(uint256 _totalCurrencyRaisedX7X7) external {
        // it returns raised in currency precision

        ValueX7X7 totalCurrencyRaisedX7X7 = ValueX7X7.wrap(_totalCurrencyRaisedX7X7);

        Checkpoint memory checkpoint;
        checkpoint.totalCurrencyRaisedX7X7 = totalCurrencyRaisedX7X7;

        uint256 result = CheckpointLib.getCurrencyRaised(checkpoint);
        assertEq(result, _totalCurrencyRaisedX7X7 / 1e14);
    }
}
