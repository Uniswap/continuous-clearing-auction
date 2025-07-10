// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAuctionStepStorage} from './interfaces/IAuctionStepStorage.sol';
import {AuctionStep} from './Base.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';

abstract contract AuctionStepStorage is IAuctionStepStorage {
    using AuctionStepLib for bytes;

    /// @notice The auction steps data from contructor parameters
    bytes public auctionStepsData;
    /// @notice Singly linked list of auction steps
    mapping(uint256 id => AuctionStep) public steps;
    /// @notice The id of the first step
    uint256 public headId;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 public offset;

    constructor(bytes memory _auctionStepsData) {
        auctionStepsData = _auctionStepsData;

    }

    /// @notice Get the current auction step
    function step() public view returns (AuctionStep memory) {
        return steps[headId];
    }

    /// @notice Advance the current auction step
    /// @dev This function is called on every new bid if the current step is complete
    function _advanceStep() internal {
        // offset is the pointer to the next step in the auctionStepsData. Each step is a uint64 (8 bytes)
        uint256 _id = headId;
        offset = _id * 8;
        uint256 _offset = offset;

        bytes memory _auctionStepsData = auctionStepsData;
        if (_offset >= _auctionStepsData.length) revert AuctionIsOver();
        (uint16 bps, uint48 blockDelta) = _auctionStepsData.get(_offset);

        _id++;
        uint256 _startBlock = block.number;
        uint256 _endBlock = _startBlock + blockDelta;

        AuctionStep storage newStep = steps[_id];
        newStep.id = _id;
        newStep.bps = bps;
        newStep.startBlock = _startBlock;
        newStep.endBlock = _endBlock;
        newStep.next = steps[headId].next;
        steps[headId].next = newStep.id;
        headId = newStep.id;

        emit AuctionStepRecorded(_id, _startBlock, _endBlock);
    }
}