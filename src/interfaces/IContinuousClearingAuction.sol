// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../libraries/CheckpointLib.sol';
import {ValueX7} from '../libraries/ValueX7Lib.sol';
import {IBidStorage} from './IBidStorage.sol';
import {ICheckpointStorage} from './ICheckpointStorage.sol';
import {IStepStorage} from './IStepStorage.sol';
import {ITickStorage} from './ITickStorage.sol';
import {ITokenCurrencyStorage} from './ITokenCurrencyStorage.sol';
import {IValidationHook} from './IValidationHook.sol';
import {IDistributionContract} from './external/IDistributionContract.sol';

/// @notice Parameters for the auction
/// @dev token and totalSupply are passed as constructor arguments
struct AuctionParameters {
    address currency; // token to raise funds in. Use address(0) for ETH
    address tokensRecipient; // address to receive leftover tokens
    address fundsRecipient; // address to receive all raised funds
    uint64 startBlock; // Block which the first step starts
    uint64 endBlock; // When the auction finishes
    uint64 claimBlock; // Block when the auction can claimed
    uint256 tickSpacing; // Fixed granularity for prices
    address validationHook; // Optional hook called before a bid
    uint256 floorPrice; // Starting floor price for the auction
    uint128 requiredCurrencyRaised; // Amount of currency required to be raised for the auction to graduate
    bytes auctionStepsData; // Packed bytes describing token issuance schedule
}

/// @notice Interface for the ContinuousClearingAuction contract
interface IContinuousClearingAuction is
    IDistributionContract,
    ICheckpointStorage,
    ITickStorage,
    IStepStorage,
    ITokenCurrencyStorage,
    IBidStorage
{
    /// @notice Error thrown when the amount received is invalid
    error InvalidTokenAmountReceived();

    /// @notice Error thrown when not enough amount is deposited
    error InvalidAmount();
    /// @notice Error thrown when the bid owner is the zero address
    error BidOwnerCannotBeZeroAddress();
    /// @notice Error thrown when the bid price is below the clearing price
    error BidMustBeAboveClearingPrice();
    /// @notice Error thrown when the bid price is too high given the auction's total supply
    error InvalidBidPriceTooHigh();
    /// @notice Error thrown when the bid amount is too small
    error BidAmountTooSmall();
    /// @notice Error thrown when msg.value is non zero when currency is not ETH
    error CurrencyIsNotNative();
    /// @notice Error thrown when the auction is not started
    error AuctionNotStarted();
    /// @notice Error thrown when the tokens required for the auction have not been received
    error TokensNotReceived();
    /// @notice Error thrown when the claim block is before the end block
    error ClaimBlockIsBeforeEndBlock();
    /// @notice Error thrown when the floor price plus tick spacing is greater than the maximum bid price
    error FloorPriceAndTickSpacingGreaterThanMaxBidPrice(uint256 nextTick, uint256 maxBidPrice);
    /// @notice Error thrown when the floor price plus tick spacing would overflow a uint256
    error FloorPriceAndTickSpacingTooLarge();
    /// @notice Error thrown when the bid has already been exited
    error BidAlreadyExited();
    /// @notice Error thrown when the bid is higher than the clearing price
    error CannotExitBid();
    /// @notice Error thrown when the bid cannot be partially exited before the end block
    error CannotPartiallyExitBidBeforeEndBlock();
    /// @notice Error thrown when the last fully filled checkpoint hint is invalid
    error InvalidLastFullyFilledCheckpointHint();
    /// @notice Error thrown when the outbid block checkpoint hint is invalid
    error InvalidOutbidBlockCheckpointHint();
    /// @notice Error thrown when the bid is not claimable
    error NotClaimable();
    /// @notice Error thrown when the bids are not owned by the same owner
    error BatchClaimDifferentOwner(address expectedOwner, address receivedOwner);
    /// @notice Error thrown when the bid has not been exited
    error BidNotExited();
    /// @notice Error thrown when the bid cannot be partially exited before the auction has graduated
    error CannotPartiallyExitBidBeforeGraduation();
    /// @notice Error thrown when the token transfer fails
    error TokenTransferFailed();
    /// @notice Error thrown when the auction is not over
    error AuctionIsNotOver();
    /// @notice Error thrown when the bid is too large
    error InvalidBidUnableToClear();
    /// @notice Error thrown when the auction has sold the entire total supply of tokens
    error AuctionSoldOut();

    /// @notice Emitted when the tokens are received
    /// @param totalSupply The total supply of tokens received
    event TokensReceived(uint256 totalSupply);

    /// @notice Emitted when a bid is submitted
    /// @param id The id of the bid
    /// @param owner The owner of the bid
    /// @param price The price of the bid
    /// @param amount The amount of the bid
    event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, uint128 amount);

    /// @notice Emitted when a new checkpoint is created
    /// @param blockNumber The block number of the checkpoint
    /// @param clearingPrice The clearing price of the checkpoint
    /// @param cumulativeMps The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)
    event CheckpointUpdated(uint256 blockNumber, uint256 clearingPrice, uint24 cumulativeMps);

    /// @notice Emitted when the clearing price is updated
    /// @param blockNumber The block number when the clearing price was updated
    /// @param clearingPrice The new clearing price
    event ClearingPriceUpdated(uint256 blockNumber, uint256 clearingPrice);

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
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param prevTickPrice The price of the previous tick
    /// @param hookData Additional data to pass to the hook required for validation
    /// @return bidId The id of the bid
    function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
        external
        payable
        returns (uint256 bidId);

    /// @notice Submit a new bid without specifying the previous tick price
    /// @dev It is NOT recommended to use this function unless you are sure that `maxPrice` is already initialized
    ///      as this function will iterate through every tick starting from the floor price if it is not.
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param hookData Additional data to pass to the hook required for validation
    /// @return bidId The id of the bid
    function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
        external
        payable
        returns (uint256 bidId);

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    /// @dev If the auction is over, it returns the final checkpoint
    /// @return _checkpoint The checkpoint at the current block
    function checkpoint() external returns (Checkpoint memory _checkpoint);

    /// @notice Whether the auction has graduated as of the given checkpoint
    /// @dev The auction is considered `graudated` if the total currency raised exceeds the required currency raised
    /// @dev Be aware that the latest checkpoint may be out of date
    /// @return bool True if the auction has graduated, false otherwise
    function isGraduated() external view returns (bool);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev This may be less than the balance of this contract if there are outstanding refunds for bidders
    /// @dev Be aware that the latest checkpoint may be out of date
    /// @return The currency raised
    function currencyRaised() external view returns (uint256);

    /// @notice Exit a bid
    /// @dev This function can only be used for bids where the max price is above the final clearing price after the auction has ended
    /// @param bidId The id of the bid
    function exitBid(uint256 bidId) external;

    /// @notice Exit a bid which has been partially filled
    /// @dev This function can be used only for partially filled bids. For fully filled bids, `exitBid` must be used
    /// @param bidId The id of the bid
    /// @param lastFullyFilledCheckpointBlock The last checkpointed block where the clearing price is strictly < bid.maxPrice
    /// @param outbidBlock The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction
    function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 outbidBlock) external;

    /// @notice Claim tokens after the auction's claim block
    /// @notice The bid must be exited before claiming tokens
    /// @dev Anyone can claim tokens for any bid, the tokens are transferred to the bid owner
    /// @param bidId The id of the bid
    function claimTokens(uint256 bidId) external;

    /// @notice Claim tokens for multiple bids
    /// @dev Anyone can claim tokens for bids of the same owner, the tokens are transferred to the owner
    /// @dev A TokensClaimed event is emitted for each bid but only one token transfer will be made
    /// @param owner The owner of the bids
    /// @param bidIds The ids of the bids
    function claimTokensBatch(address owner, uint256[] calldata bidIds) external;

    /// @notice Withdraw all of the currency raised
    /// @dev Can be called by anyone after the auction has ended
    function sweepCurrency() external;

    /// @notice The block at which the auction can be claimed
    function claimBlock() external view returns (uint64);

    /// @notice The address of the validation hook for the auction
    function validationHook() external view returns (IValidationHook);

    /// @notice Sweep any leftover tokens to the tokens recipient
    /// @dev This function can only be called after the auction has ended
    function sweepUnsoldTokens() external;

    /// @notice The currency raised as of the last checkpoint
    function currencyRaisedQ96_X7() external view returns (ValueX7);

    /// @notice The sum of demand in ticks above the clearing price
    function sumCurrencyDemandAboveClearingQ96() external view returns (uint256);

    /// @notice The total currency raised as of the last checkpoint
    function totalClearedQ96_X7() external view returns (ValueX7);

    /// @notice The total tokens cleared as of the last checkpoint in uint256 representation
    function totalCleared() external view returns (uint256);
}
