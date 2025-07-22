// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAuctionStepStorage} from './interfaces/IAuctionStepStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';

/// @title AuctionStepStorage
/// @notice Abstract contract to store and read information about the auction issuance schedule
abstract contract AuctionStepStorage is IAuctionStepStorage {
    using AuctionStepLib for *;
    using SSTORE2 for *;

    /// @notice The size of a uint64 in bytes
    uint256 public constant UINT64_SIZE = 8;
    /// @notice The block at which the auction starts
    uint64 public immutable startBlock;
    /// @notice The block at which the auction ends
    uint64 public immutable endBlock;
    /// @notice Cached length of the auction steps data provided in the constructor
    uint256 private immutable _length;

    /// @notice The address pointer to the contract deployed by SSTORE2
    address public pointer;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 public offset;
    /// @notice The current active auction step
    AuctionStep public step;

    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock) {
        startBlock = _startBlock;
        endBlock = _endBlock;

        _length = _auctionStepsData.length;

        address _pointer = _auctionStepsData.write();
        if (_pointer == address(0)) revert InvalidPointer();

        _validate(_pointer);
        pointer = _pointer;
    }

    /// @notice Validate the data provided in the constructor
    /// @dev Checks that the contract was correctly deployed by SSTORE2 and that the total bps and blocks are valid
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

        bytes8 _auctionStep = bytes8(pointer.read(offset, offset + UINT64_SIZE));
        (uint16 bps, uint48 blockDelta) = _auctionStep.parse();

        uint64 _startBlock = step.endBlock;
        if (_startBlock == 0) _startBlock = startBlock;
        uint64 _endBlock = _startBlock + uint64(blockDelta);

        step.bps = bps;
        step.startBlock = _startBlock;
        step.endBlock = _endBlock;

        offset += UINT64_SIZE;

        emit AuctionStepRecorded(bps, _startBlock, _endBlock);
    }
}
