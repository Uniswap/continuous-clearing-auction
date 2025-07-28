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
    /// @notice Error thrown when the bid is not owned by the caller
    error NotBidOwner();
    /// @notice Error thrown when the bid has already been withdrawn
    error BidAlreadyWithdrawn();
    /// @notice Error thrown when the bid is higher than the clearing price
    error CannotWithdrawBid();
    /// @notice Error thrown when the checkpoint hint is invalid
    error InvalidCheckpointHint();
    /// @notice Error thrown when the bid is not claimable
    error NotClaimable();
    /// @notice Error thrown when the bid has not been withdrawn
    error BidNotWithdrawn();

    /// @notice Emitted when a bid is submitted
    /// @param id The id of the bid
    /// @param price The price of the bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, bool exactIn, uint256 amount);

    /// @notice Emitted when a new checkpoint is created
    /// @param blockNumber The block number of the checkpoint
    /// @param clearingPrice The clearing price of the checkpoint
    /// @param totalCleared The total amount of tokens cleared
    /// @param cumulativeMps The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)
    event CheckpointUpdated(
        uint256 indexed blockNumber, uint256 clearingPrice, uint256 totalCleared, uint24 cumulativeMps
    );

    /// @notice Emitted when a bid is withdrawn
    /// @param bidId The id of the bid
    /// @param owner The owner of the bid
    event BidWithdrawn(uint256 indexed bidId, address indexed owner);

    /// @notice Emitted when a bid is claimed
    /// @param owner The owner of the bid
    /// @param tokensFilled The amount of tokens claimed
    event TokensClaimed(address indexed owner, uint256 tokensFilled);

    /// @notice Submit a new bid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevHintId The id of the previous tick hint
    /// @param hookData Additional data to pass to the hook required for validation
    function submitBid(uint128 maxPrice, bool exactIn, uint256 amount, address owner, uint128 prevHintId, bytes calldata hookData)
        external
        payable;

    /// @notice Withdraw a bid
    /// @dev A bid can only be withdrawn if the maxPrice is below the current clearing price
    /// @param bidId The id of the bid
    /// @param upperCheckpointId The id of the checkpoint immediately after the last "active" checkpoint for the bid
    function withdrawBid(uint256 bidId, uint256 upperCheckpointId) external;

    /// @notice Claim tokens after the auction's claim block
    /// @notice The bid must be withdrawn before claiming tokens
    /// @dev Anyone can claim tokens for any bid, the tokens are transferred to the bid owner
    /// @param bidId The id of the bid
    function claimTokens(uint256 bidId) external;
}
