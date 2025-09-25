// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../libraries/CheckpointLib.sol';
import {ValueX7} from '../libraries/MPSLib.sol';
import {IAuctionStepStorage} from './IAuctionStepStorage.sol';

import {ICheckpointStorage} from './ICheckpointStorage.sol';
import {ITickStorage} from './ITickStorage.sol';
import {ITokenCurrencyStorage} from './ITokenCurrencyStorage.sol';
import {IValidationHook} from './IValidationHook.sol';
import {IDistributionContract} from './external/IDistributionContract.sol';

/// @notice Parameters for auction deployment
/// @dev Token and totalSupply are passed as constructor arguments
struct AuctionParameters {
    address currency; // Currency to raise funds in (address(0) for ETH)
    address tokensRecipient; // Address to receive unsold tokens
    address fundsRecipient; // Address to receive raised currency
    uint64 startBlock; // Block when auction starts
    uint64 endBlock; // Block when auction ends
    uint64 claimBlock; // Block when tokens can be claimed
    uint24 graduationThresholdMps; // Minimum MPS to graduate
    uint256 tickSpacing; // Price granularity
    address validationHook; // Optional validation hook
    uint256 floorPrice; // Minimum auction price
    bytes auctionStepsData; // Packed MPS schedule data
}

/// @notice Main auction interface
/// @dev Inherits from storage interfaces for complete functionality
interface IAuction is
    IDistributionContract,
    ICheckpointStorage,
    ITickStorage,
    IAuctionStepStorage,
    ITokenCurrencyStorage
{
    /// @notice Token balance insufficient for auction initialization
    error IDistributionContract__InvalidAmountReceived();
    /// @notice Bid amount is invalid (zero or insufficient)
    error InvalidAmount();
    /// @notice Auction has not started yet (before startBlock)
    error AuctionNotStarted();
    /// @notice Auction tokens have not been received via onTokensReceived()
    error TokensNotReceived();
    /// @notice Floor price cannot be zero
    error FloorPriceIsZero();
    /// @notice Tick spacing cannot be zero
    error TickSpacingIsZero();
    /// @notice Claim block must be >= end block
    error ClaimBlockIsBeforeEndBlock();
    /// @notice Bid has already been exited
    error BidAlreadyExited();
    /// @notice Cannot exit bid (max price <= final clearing price)
    error CannotExitBid();
    /// @notice Checkpoint hint parameters are invalid for partial exit
    error InvalidCheckpointHint();
    /// @notice Bid is not eligible for token claiming
    error NotClaimable();
    /// @notice Bid must be exited before claiming tokens
    error BidNotExited();
    /// @notice Token transfer operation failed
    error TokenTransferFailed();
    /// @notice Auction is still active (before endBlock)
    error AuctionIsNotOver();
    /// @notice Bid price must be above current clearing price
    error InvalidBidPrice();

    /// @notice Emitted when the tokens are received
    /// @param totalSupply The total supply of tokens received
    event TokensReceived(uint256 totalSupply);

    /// @notice Emitted when a bid is submitted
    /// @param id The id of the bid
    /// @param owner The owner of the bid
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
        uint256 indexed blockNumber, uint256 clearingPrice, ValueX7 totalCleared, uint24 cumulativeMps
    );

    /// @notice Emitted when a bid is exited
    /// @param bidId The id of the bid
    /// @param owner The owner of the bid
    /// @param tokensFilled The amount of tokens filled
    /// @param currencyRefunded The amount of currency refunded
    event BidExited(uint256 indexed bidId, address indexed owner, uint256 tokensFilled, uint256 currencyRefunded);

    /// @notice Emitted when a bid is claimed
    /// @param bidId The id of the bid
    /// @param owner The owner of the bid
    /// @param tokensFilled The amount of tokens claimed
    event TokensClaimed(uint256 indexed bidId, address indexed owner, uint256 tokensFilled);

    /// @notice Submit a new bid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevTickPrice The price of the previous tick for insertion hint
    /// @param hookData Additional data to pass to the validation hook
    /// @return bidId The id of the bid
    function submitBid(
        uint256 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable returns (uint256 bidId);

    /// @notice Create a checkpoint at the current block
    /// @dev Called automatically during bid submission or manually
    function checkpoint() external returns (Checkpoint memory _checkpoint);

    /// @notice Whether the auction has graduated
    /// @dev Returns true if enough tokens were sold to meet the graduation threshold
    function isGraduated() external view returns (bool);

    /// @notice Exit a bid that was not filled
    /// @dev Only for bids where max price > final clearing price
    /// @param bidId The id of the bid
    function exitBid(uint256 bidId) external;

    /// @notice Exit a partially filled bid with checkpoint hints
    /// @param bidId The id of the bid
    /// @param lower The last checkpoint where clearing price < bid.maxPrice
    /// @param outbidBlock The first checkpoint where clearing price > bid.maxPrice
    function exitPartiallyFilledBid(uint256 bidId, uint64 lower, uint64 outbidBlock) external;

    /// @notice Claim tokens for an exited bid
    /// @dev Requires auction graduation and past claimBlock
    /// @param bidId The id of the bid
    function claimTokens(uint256 bidId) external;

    /// @notice Withdraw all raised currency
    /// @dev Only callable by funds recipient for graduated auctions
    function sweepCurrency() external;

    /// @notice Returns the block number when tokens become claimable
    function claimBlock() external view returns (uint64);

    /// @notice Returns the validation hook address (or address(0) if none)
    function validationHook() external view returns (IValidationHook);

    /// @notice Sweep unsold tokens to the tokens recipient
    /// @dev Callable after auction ends
    function sweepUnsoldTokens() external;
}
