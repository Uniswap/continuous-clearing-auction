// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStep} from './Base.sol';
import {IAuctionStepStorage} from './interfaces/IAuctionStepStorage.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';

abstract contract AuctionStepStorage is IAuctionStepStorage {
    using AuctionStepLib for bytes;
    using SSTORE2 for *;

    error InvalidAuctionDataLength();
    error InvalidBps();
    error InvalidEndBlock();

    /// @notice The block at which the auction starts
    uint64 public immutable startBlock;
    /// @notice The block at which the auction ends
    uint64 public immutable endBlock;

    address public pointer;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 public offset;
    uint256 public constant UINT64_SIZE = 8;

    uint256 private immutable _length;

    AuctionStep public step;

    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock) {
        startBlock = _startBlock;
        endBlock = _endBlock;

        _length = _auctionStepsData.length;

        address _pointer = _auctionStepsData.write();
        require(_pointer != address(0), 'Invalid pointer');

        _validate(_pointer);
        pointer = _pointer;
    }

    function _validate(address _pointer) private view {
        bytes memory _auctionStepsData = _pointer.read();
        if (
            _auctionStepsData.length == 0 || _auctionStepsData.length % UINT64_SIZE != 0
                || _auctionStepsData.length != _length
        ) revert InvalidAuctionDataLength();
        // Loop through the auction steps data and check if the bps is valid
        uint256 sumBps;
        uint64 sumBlockDelta;
        for (uint256 i = 0; i < _length; i += UINT64_SIZE) {
            (uint16 bps, uint48 blockDelta) = _auctionStepsData.get(i);
            sumBps += bps * blockDelta;
            sumBlockDelta += blockDelta;
        }
        if (sumBps != AuctionStepLib.BPS) revert InvalidBps();
        if (sumBlockDelta + startBlock != endBlock) revert InvalidEndBlock();
    }

    /// @notice Advance the current auction step
    /// @dev This function is called on every new bid if the current step is complete
    function _advanceStep() internal {
        if (offset > _length) revert AuctionIsOver();

        bytes memory _auctionStep = pointer.read(offset, offset + UINT64_SIZE);
        (uint16 bps, uint48 blockDelta) = _auctionStep.get(0);

        uint64 _startBlock = uint64(block.number);
        uint64 _endBlock = _startBlock + uint64(blockDelta);

        step.bps = bps;
        step.startBlock = _startBlock;
        step.endBlock = _endBlock;

        offset += UINT64_SIZE;

        emit AuctionStepRecorded(bps, _startBlock, _endBlock);
    }
}
