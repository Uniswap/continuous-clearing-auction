// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionStepStorage} from 'twap-auction/AuctionStepStorage.sol';
import {AuctionStep} from 'twap-auction/libraries/AuctionStepLib.sol';

contract MockAuctionStepStorage is AuctionStepStorage {
    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock)
        AuctionStepStorage(_auctionStepsData, _startBlock, _endBlock)
    {}

    function advanceStep() public returns (AuctionStep memory) {
        return _advanceStep();
    }

    function validate(address _pointer) public view {
        _validate(_pointer);
    }
}
