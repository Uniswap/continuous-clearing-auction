// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITickStorage} from './ITickStorage.sol';

/// @notice Interface for the Auction contract
interface IAuction is ITickStorage {
    /// @notice Error thrown when the auction is not started
    error AuctionNotStarted();
    /// @notice Error thrown when the current step is not complete
    error AuctionStepNotOver();
    /// @notice Error thrown when the auction is over
    error AuctionIsOver();
    /// @notice Error thrown when the total supply is zero
    error TotalSupplyIsZero();
    /// @notice Error thrown when the floor price is zero
    error FloorPriceIsZero();
    /// @notice Error thrown when the tick spacing is zero
    error TickSpacingIsZero();
    /// @notice Error thrown when the end block is before the start block
    error EndBlockIsBeforeStartBlock();
    /// @notice Error thrown when the end block is too large
    error EndBlockIsTooLarge();
    /// @notice Error thrown when the claim block is before the end block
    error ClaimBlockIsBeforeEndBlock();
    /// @notice Error thrown when the token recipient is the zero address
    error TokenRecipientIsZero();
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();

    /// @notice Emitted when an auction step is recorded
    /// @param id The id of the auction step
    /// @param startBlock The start block of the auction step
    /// @param endBlock The end block of the auction step
    event AuctionStepRecorded(uint256 indexed id, uint256 startBlock, uint256 endBlock);
    /// @notice Emitted when a bid is submitted
    /// @param id The id of the tick
    /// @param price The price of the bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    event BidSubmitted(uint128 indexed id, uint256 price, bool exactIn, uint256 amount);
    /// @notice Emitted when the clearing price is updateds
    /// @param oldPrice The old clearing price
    /// @param newPrice The new clearing price
    event ClearingPriceUpdated(uint256 oldPrice, uint256 newPrice);

    /// @notice Submit a new bid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevHintId The id of the previous tick hint
    function submitBid(uint128 maxPrice, bool exactIn, uint128 amount, address owner, uint128 prevHintId) external;
}
