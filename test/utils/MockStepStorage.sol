// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StepStorage} from '../../src/StepStorage.sol';

/// @notice Mock auction step storage for testing
contract MockStepStorage is StepStorage {
    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock)
        StepStorage(_auctionStepsData, _startBlock, _endBlock)
    {}

    function advanceStep() public {
        _advanceStep();
    }
}
