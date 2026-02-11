// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IStepStorage} from './interfaces/IStepStorage.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {AuctionStep, StepLib} from './libraries/StepLib.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';

/// @title StepStorage
/// @notice Abstract contract to store and read information about the auction issuance schedule
abstract contract StepStorage is BlockNumberish, IStepStorage {
    using StepLib for *;
    using SSTORE2 for *;

    /// @notice The block at which the auction starts
    uint64 internal immutable START_BLOCK;
    /// @notice The block at which the auction ends
    uint64 internal immutable END_BLOCK;
    /// @notice The block at which purchased tokens can be claimed
    uint64 internal immutable CLAIM_BLOCK;
    /// @notice Cached length of the auction steps data provided in the constructor
    uint256 internal immutable _LENGTH;

    /// @notice The address pointer to the contract deployed by SSTORE2
    address private immutable $_pointer;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 private $_offset;
    /// @notice The current active auction step
    AuctionStep internal $step;

    constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock, uint64 _claimBlock) {
        if (_startBlock >= _endBlock) revert InvalidEndBlock();
        if (_claimBlock < _endBlock) revert ClaimBlockIsBeforeEndBlock();

        START_BLOCK = _startBlock;
        END_BLOCK = _endBlock;
        CLAIM_BLOCK = _claimBlock;
        _LENGTH = _auctionStepsData.length;

        address _pointer = _auctionStepsData.write();
        _validate(_pointer);
        $_pointer = _pointer;

        _advanceStep();
    }

    /// @notice Modifier for functions which can only be called after the auction is over
    modifier onlyAfterAuctionIsOver() {
        if (_getBlockNumberish() < END_BLOCK) revert AuctionIsNotOver();
        _;
    }

    /// @notice Modifier for claim related functions which can only be called after the claim block
    modifier onlyAfterClaimBlock() {
        if (_getBlockNumberish() < CLAIM_BLOCK) revert NotClaimable();
        _;
    }

    /// @notice Fast forward to the start of the current step and return the number of `mps` sold since the last checkpoint
    /// @param _blockNumber The current block number
    /// @param _lastCheckpointedBlock The block number of the last checkpointed block
    /// @return _step The current step in the auction which contains `_blockNumber`
    /// @return deltaMps The number of `mps` sold between the last checkpointed block and the start of the current step
    function _advanceToStartOfCurrentStep(uint64 _blockNumber, uint64 _lastCheckpointedBlock)
        internal
        returns (AuctionStep memory _step, uint24 deltaMps)
    {
        // Advance the current step until the current block is within the step
        // Start at the larger of the last checkpointed block or the start block of the current step
        _step = $step;
        uint64 start = uint64(FixedPointMathLib.max(_step.startBlock, _lastCheckpointedBlock));
        uint64 end = _step.endBlock;

        uint24 mps = _step.mps;
        while (_blockNumber > end) {
            uint64 blockDelta = end - start;
            unchecked {
                deltaMps += uint24(blockDelta * mps);
            }
            start = end;
            if (end == END_BLOCK) break;
            _step = _advanceStep();
            mps = _step.mps;
            end = _step.endBlock;
        }
    }

    /// @notice Validate the data provided in the constructor
    /// @dev Checks that the contract was correctly deployed by SSTORE2 and that the total mps and blocks are valid
    function _validate(address _pointer) internal view {
        bytes memory _auctionStepsData = _pointer.read();
        if (
            _auctionStepsData.length == 0 || _auctionStepsData.length % StepLib.UINT64_SIZE != 0
                || _auctionStepsData.length != _LENGTH
        ) revert InvalidAuctionDataLength();

        // Loop through the auction steps data and check if the mps is valid
        uint256 sumMps = 0;
        uint64 sumBlockDelta = 0;
        for (uint256 i = 0; i < _LENGTH; i += StepLib.UINT64_SIZE) {
            (uint24 mps, uint40 blockDelta) = _auctionStepsData.get(i);
            // Prevent the block delta from being set to zero
            if (blockDelta == 0) revert StepBlockDeltaCannotBeZero();
            sumMps += mps * blockDelta;
            sumBlockDelta += blockDelta;
        }
        if (sumMps != ConstantsLib.MPS) revert InvalidStepDataMps(sumMps, ConstantsLib.MPS);
        uint64 calculatedEndBlock = START_BLOCK + sumBlockDelta;
        if (calculatedEndBlock != END_BLOCK) revert InvalidEndBlockGivenStepData(calculatedEndBlock, END_BLOCK);
    }

    /// @notice Advance the current auction step
    /// @dev This function is called on every new bid if the current step is complete
    function _advanceStep() internal returns (AuctionStep memory) {
        if ($_offset >= _LENGTH) revert AuctionIsOver();

        bytes8 _auctionStep = bytes8($_pointer.read($_offset, $_offset + StepLib.UINT64_SIZE));
        (uint24 mps, uint40 blockDelta) = _auctionStep.parse();

        uint64 _startBlock = $step.endBlock;
        if (_startBlock == 0) _startBlock = START_BLOCK;
        uint64 _endBlock = _startBlock + uint64(blockDelta);

        $step = AuctionStep({startBlock: _startBlock, endBlock: _endBlock, mps: mps});

        $_offset += StepLib.UINT64_SIZE;

        emit AuctionStepRecorded(_startBlock, _endBlock, mps);
        return $step;
    }

    /// @inheritdoc IStepStorage
    function step() external view returns (AuctionStep memory) {
        return $step;
    }

    // Getters
    /// @inheritdoc IStepStorage
    function pointer() external view returns (address) {
        return $_pointer;
    }
}
