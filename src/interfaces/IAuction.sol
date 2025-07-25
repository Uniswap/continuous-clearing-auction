// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAuctionStepStorage} from './IAuctionStepStorage.sol';
import {ITickStorage} from './ITickStorage.sol';
import {IDistributionContract} from './external/IDistributionContract.sol';

/// @notice Interface for the Auction contract
interface IAuction is IDistributionContract, ITickStorage, IAuctionStepStorage {
    /// @notice Error thrown when the token is invalid
    error IDistributionContract__InvalidToken();
    /// @notice Error thrown when the amount is invalid
    error IDistributionContract__InvalidAmount();
    /// @notice Error thrown when the amount received is invalid
    error IDistributionContract__InvalidAmountReceived();

    /// @notice Error thrown when not enough amount is deposited
    error InvalidAmount();
    /// @notice Error thrown when the auction is not started
    error AuctionNotStarted();
    /// @notice Error thrown when the current step is not complete
    error AuctionStepNotOver();
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
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();

    /// @notice Emitted when a bid is submitted
    /// @param id The id of the tick
    /// @param price The price of the bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    event BidSubmitted(uint128 indexed id, uint256 price, bool exactIn, uint256 amount);

    /// @notice Emitted when a new checkpoint is created
    /// @param blockNumber The block number of the checkpoint
    /// @param clearingPrice The clearing price of the checkpoint
    /// @param totalCleared The total amount of tokens cleared
    /// @param cumulativeMps The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)
    event CheckpointUpdated(
        uint256 indexed blockNumber, uint256 clearingPrice, uint256 totalCleared, uint24 cumulativeMps
    );

    /// @notice Submit a new bid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevHintId The id of the previous tick hint
    function submitBid(uint128 maxPrice, bool exactIn, uint256 amount, address owner, uint128 prevHintId)
        external
        payable;
}
