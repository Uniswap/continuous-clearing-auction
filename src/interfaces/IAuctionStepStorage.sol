// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStep} from '../libraries/AuctionStepLib.sol';

/// @notice Interface for managing auction step storage
interface IAuctionStepStorage {
    /// @notice Error thrown when the end block is equal to or before the start block
    error InvalidEndBlock();
    /// @notice Error thrown when the auction is over
    error AuctionIsOver();
    /// @notice Error thrown when the auction data length is invalid
    error InvalidAuctionDataLength();
    /// @notice Error thrown when the block delta in a step is zero
    error StepBlockDeltaCannotBeZero();
    /// @notice Error thrown when the mps is invalid
    /// @param actualMps The sum of the mps times the block delta
    /// @param expectedMps The expected mps of the auction (ConstantsLib.MPS)
    error InvalidStepDataMps(uint256 actualMps, uint256 expectedMps);
    /// @notice Error thrown when the calculated end block is invalid
    /// @param actualEndBlock The calculated end block from the step data
    /// @param expectedEndBlock The expected end block from the constructor
    error InvalidEndBlockGivenStepData(uint64 actualEndBlock, uint64 expectedEndBlock);

    /// @notice The block at which the auction starts
    /// @return The starting block number
    function startBlock() external view returns (uint64);
    /// @notice The block at which the auction ends
    /// @return The ending block number
    function endBlock() external view returns (uint64);

    /// @notice The address pointer to the contract deployed by SSTORE2
    /// @return The address pointer
    function pointer() external view returns (address);

    /// @notice Get the current active auction step
    function step() external view returns (AuctionStep memory);

    /// @notice Emitted when an auction step is recorded
    /// @param startBlock The start block of the auction step
    /// @param endBlock The end block of the auction step
    /// @param mps The percentage of total tokens to sell per block during this auction step, represented in ten-millionths of the total supply (1e7 = 100%)
    event AuctionStepRecorded(uint256 startBlock, uint256 endBlock, uint24 mps);
}
