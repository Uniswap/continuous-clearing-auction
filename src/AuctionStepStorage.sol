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
    /// @inheritdoc IAuctionStepStorage
    uint64 public immutable startBlock;
    /// @inheritdoc IAuctionStepStorage
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

        _advanceStep();
    }

    /// @notice Validate the data provided in the constructor
    /// @dev Checks that the contract was correctly deployed by SSTORE2 and that the total mps and blocks are valid
    function _validate(address _pointer) private view {
        bytes memory _auctionStepsData = _pointer.read();
        if (
            _auctionStepsData.length == 0 || _auctionStepsData.length % UINT64_SIZE != 0
                || _auctionStepsData.length != _length
        ) revert InvalidAuctionDataLength();

        // Loop through the auction steps data and check if the mps is valid
        uint256 sumMps;
        uint64 sumBlockDelta;
        for (uint256 i = 0; i < _length; i += UINT64_SIZE) {
            (uint24 mps, uint40 blockDelta) = _auctionStepsData.get(i);
            sumMps += mps * blockDelta;
            sumBlockDelta += blockDelta;
        }
        if (sumMps != AuctionStepLib.MPS) revert InvalidMps();
        if (sumBlockDelta + startBlock != endBlock) revert InvalidEndBlock();
    }

    /// @notice Advance the current auction step
    /// @dev This function is called on every new bid if the current step is complete
    function _advanceStep() internal {
        if (offset > _length) revert AuctionIsOver();

        bytes8 _auctionStep = bytes8(pointer.read(offset, offset + UINT64_SIZE));
        (uint24 mps, uint40 blockDelta) = _auctionStep.parse();

        uint64 _startBlock = step.endBlock;
        if (_startBlock == 0) _startBlock = startBlock;
        uint64 _endBlock = _startBlock + uint64(blockDelta);

        step.mps = mps;
        step.startBlock = _startBlock;
        step.endBlock = _endBlock;

        offset += UINT64_SIZE;

        emit AuctionStepRecorded(_startBlock, _endBlock, mps);
    }
}
