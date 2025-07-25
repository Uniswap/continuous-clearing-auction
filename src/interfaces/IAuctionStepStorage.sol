// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAuctionStepStorage {
    /// @notice Error thrown when the SSTORE2 pointer is the zero address
    error InvalidPointer();
    /// @notice Error thrown when the auction is over
    error AuctionIsOver();
    /// @notice Error thrown when the auction data length is invalid
    error InvalidAuctionDataLength();
    /// @notice Error thrown when the bps is invalid
    error InvalidBps();
    /// @notice Error thrown when the end block is invalid
    error InvalidEndBlock();

    /// @notice Emitted when an auction step is recorded
    /// @param bps The basis points of the auction step
    /// @param startBlock The start block of the auction step
    /// @param endBlock The end block of the auction step
    event AuctionStepRecorded(uint16 bps, uint256 startBlock, uint256 endBlock);
}
