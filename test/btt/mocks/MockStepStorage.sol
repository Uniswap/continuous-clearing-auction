// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StepStorage} from 'continuous-clearing-auction/StepStorage.sol';
import {AuctionStep} from 'continuous-clearing-auction/libraries/StepLib.sol';

contract MockStepStorage is StepStorage {
    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock)
        StepStorage(_auctionStepsData, _startBlock, _endBlock)
    {}

    function advanceStep() public returns (AuctionStep memory) {
        return _advanceStep();
    }

    function validate(address _pointer) public view {
        _validate(_pointer);
    }
}
