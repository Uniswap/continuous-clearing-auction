// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStepStorage} from './interfaces/IAuctionStepStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {MPSLib} from './libraries/MPSLib.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';

/// @title AuctionStepStorage
/// @notice Manages time-weighted token issuance schedule
/// @dev Uses SSTORE2 for gas-efficient storage. Validates that sum(mps * blockDelta) equals MPSLib.MPS.
abstract contract AuctionStepStorage is IAuctionStepStorage {
    using AuctionStepLib for *;
    using SSTORE2 for *;

    /// @notice Size of each packed auction step
    uint256 public constant UINT64_SIZE = 8;
    /// @notice Block when auction starts
    uint64 internal immutable START_BLOCK;
    /// @notice Block when auction ends
    uint64 internal immutable END_BLOCK;
    /// @notice Length of auction steps data
    uint256 internal immutable _LENGTH;

    /// @notice SSTORE2 pointer to step data
    address public pointer;
    /// @notice Current reading offset in step data
    uint256 public offset;
    /// @notice Current active auction step
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

    /// @notice Validates auction step data integrity and mathematical constraints
    /// @dev Performs comprehensive validation:
    ///      1. Checks SSTORE2 deployment success and data length alignment
    ///      2. Validates that sum(mps * blockDelta) == MPSLib.MPS for proper token distribution
    ///      3. Ensures sum(blockDelta) + START_BLOCK == END_BLOCK for timing consistency
    ///      This prevents invalid supply schedules that could break auction mechanics.
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

    /// @notice Advances to the next auction step when the current step period ends
    /// @dev Called during checkpoint updates when block.number exceeds current step.endBlock.
    ///      Reads the next packed step data from SSTORE2 storage, updates the step state,
    ///      and increments the offset. Reverts if attempting to advance past the final step.
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
