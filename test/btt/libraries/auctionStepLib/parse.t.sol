// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {StepLib} from 'continuous-clearing-auction/libraries/StepLib.sol';

contract ParseTest is BttBase {
    function test_WhenCalledWith8BytesOfData(uint24 _mps, uint40 _blockDelta) external {
        // it returns mps and block delta
        uint256 value = uint256(_mps) << 40 | uint256(_blockDelta);
        bytes8 data = bytes8(uint64(value));

        (uint24 mps, uint40 blockDelta) = StepLib.parse(data);

        assertEq(mps, _mps);
        assertEq(blockDelta, _blockDelta);
    }
}
