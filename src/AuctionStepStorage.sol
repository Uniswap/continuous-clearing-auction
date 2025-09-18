// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStepStorage} from './interfaces/IAuctionStepStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {MPSLib} from './libraries/MPSLib.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';

/// @title AuctionStepStorage
/// @notice Abstract contract to store and read information about the auction issuance schedule
abstract contract AuctionStepStorage is IAuctionStepStorage {
    using AuctionStepLib for *;
    using SSTORE2 for *;

    /// @notice The size of a uint64 in bytes
    uint256 public constant UINT64_SIZE = 8;
    /// @notice The block at which the auction starts
    uint64 internal immutable START_BLOCK;
    /// @notice The block at which the auction ends
    uint64 internal immutable END_BLOCK;
    /// @notice Cached length of the auction steps data provided in the constructor
    uint256 internal immutable _LENGTH;

    /// @notice The address pointer to the contract deployed by SSTORE2
    address public pointer;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 public offset;
    /// @notice The current active auction step
    AuctionStep public step;

    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock) {
        START_BLOCK = _startBlock;
        END_BLOCK = _endBlock;

        _LENGTH = _auctionStepsData.length;

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
                || _auctionStepsData.length != _LENGTH
        ) revert InvalidAuctionDataLength();

        // Loop through the auction steps data and check if the mps is valid
        uint256 sumMps;
        uint64 sumBlockDelta;
        for (uint256 i = 0; i < _LENGTH; i += UINT64_SIZE) {
            (uint24 mps, uint40 blockDelta) = _auctionStepsData.get(i);
            sumMps += mps * blockDelta;
            sumBlockDelta += blockDelta;
        }
        if (sumMps != MPSLib.MPS) revert InvalidMps();
        if (sumBlockDelta + START_BLOCK != END_BLOCK) revert InvalidEndBlock();
    }

    /// @notice Advance the current auction step
    /// @dev This function is called on every new bid if the current step is complete
    function _advanceStep() internal returns (AuctionStep memory) {
        if (offset > _LENGTH) revert AuctionIsOver();

        bytes8 _auctionStep = bytes8(pointer.read(offset, offset + UINT64_SIZE));
        (uint24 mps, uint40 blockDelta) = _auctionStep.parse();

        uint64 _startBlock = step.endBlock;
        if (_startBlock == 0) _startBlock = START_BLOCK;
        uint64 _endBlock = _startBlock + uint64(blockDelta);

        step = AuctionStep({startBlock: _startBlock, endBlock: _endBlock, mps: mps});

        offset += UINT64_SIZE;

        emit AuctionStepRecorded(_startBlock, _endBlock, mps);
        return step;
    }

    // Getters
    /// @inheritdoc IAuctionStepStorage
    function startBlock() external view returns (uint64) {
        return START_BLOCK;
    }

    /// @inheritdoc IAuctionStepStorage
    function endBlock() external view returns (uint64) {
        return END_BLOCK;
    }
}
