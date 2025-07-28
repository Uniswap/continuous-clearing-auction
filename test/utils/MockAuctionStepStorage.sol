// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepStorage} from '../../src/AuctionStepStorage.sol';

/// @notice Mock auction step storage for testing
contract MockAuctionStepStorage is AuctionStepStorage {
    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock)
        AuctionStepStorage(_auctionStepsData, _startBlock, _endBlock)
    {}

    function advanceStep() public {
        _advanceStep();
    }
}
