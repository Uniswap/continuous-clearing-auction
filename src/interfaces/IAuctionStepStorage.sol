// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IAuctionStepStorage {
    /// @notice Error thrown when the auction is over
    error AuctionIsOver();
    
    /// @notice Emitted when an auction step is recorded
    /// @param id The id of the auction step
    /// @param startBlock The start block of the auction step
    /// @param endBlock The end block of the auction step
    event AuctionStepRecorded(uint256 indexed id, uint256 startBlock, uint256 endBlock);
}