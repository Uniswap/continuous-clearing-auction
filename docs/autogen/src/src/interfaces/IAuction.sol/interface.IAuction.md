# IAuction
[Git Source](https://github.com/Uniswap/twap-auction/blob/f66249e6bb5ebf3be6698edff5f27719f8f33c6e/src/interfaces/IAuction.sol)

**Inherits:**
[IDistributionContract](/src/interfaces/external/IDistributionContract.sol/interface.IDistributionContract.md), [ICheckpointStorage](/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md), [ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md), [IAuctionStepStorage](/src/interfaces/IAuctionStepStorage.sol/interface.IAuctionStepStorage.md), [ITokenCurrencyStorage](/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md)

Interface for the Auction contract


## Functions
### submitBid

Submit a new bid


```solidity
function submitBid(
    uint256 maxPrice,
    bool exactIn,
    uint256 amount,
    address owner,
    uint256 prevTickPrice,
    bytes calldata hookData
) external payable returns (uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`prevTickPrice`|`uint256`|The price of the previous tick|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### checkpoint

Register a new checkpoint

*This function is called every time a new bid is submitted above the current clearing price*


```solidity
function checkpoint() external returns (Checkpoint memory _checkpoint);
```

### isGraduated

Whether the auction has graduated as of the latest checkpoint (sold more than the graduation threshold)


```solidity
function isGraduated() external view returns (bool);
```

### exitBid

Exit a bid

*This function can only be used for bids where the max price is above the final clearing price after the auction has ended*


```solidity
function exitBid(uint256 bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### exitPartiallyFilledBid

Exit a bid which has been partially filled

*This function can be used for fully filled or partially filled bids. For fully filled bids, `exitBid` is more efficient*


```solidity
function exitPartiallyFilledBid(uint256 bidId, uint64 lower, uint64 outbidBlock) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`lower`|`uint64`|The last checkpointed block where the clearing price is strictly < bid.maxPrice|
|`outbidBlock`|`uint64`|The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction|


### claimTokens

Claim tokens after the auction's claim block

The bid must be exited before claiming tokens

*Anyone can claim tokens for any bid, the tokens are transferred to the bid owner*


```solidity
function claimTokens(uint256 bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### sweepCurrency

Withdraw all of the currency raised

*Can only be called by the funds recipient after the auction has ended
Must be called before the `claimBlock`*


```solidity
function sweepCurrency() external;
```

### claimBlock

The block at which the auction can be claimed


```solidity
function claimBlock() external view returns (uint64);
```

### validationHook

The address of the validation hook for the auction


```solidity
function validationHook() external view returns (IValidationHook);
```

### sweepUnsoldTokens

Sweep any leftover tokens to the tokens recipient

*This function can only be called after the auction has ended*


```solidity
function sweepUnsoldTokens() external;
```

## Events
### BidSubmitted
Emitted when a bid is submitted


```solidity
event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, bool exactIn, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|
|`price`|`uint256`|The price of the bid|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|

### CheckpointUpdated
Emitted when a new checkpoint is created


```solidity
event CheckpointUpdated(uint256 indexed blockNumber, uint256 clearingPrice, ValueX7 totalCleared, uint24 cumulativeMps);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number of the checkpoint|
|`clearingPrice`|`uint256`|The clearing price of the checkpoint|
|`totalCleared`|`ValueX7`|The total amount of tokens cleared|
|`cumulativeMps`|`uint24`|The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)|

### BidExited
Emitted when a bid is exited


```solidity
event BidExited(uint256 indexed bidId, address indexed owner, uint256 tokensFilled, uint256 currencyRefunded);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|
|`tokensFilled`|`uint256`|The amount of tokens filled|
|`currencyRefunded`|`uint256`|The amount of currency refunded|

### TokensClaimed
Emitted when a bid is claimed


```solidity
event TokensClaimed(uint256 indexed bidId, address indexed owner, uint256 tokensFilled);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|
|`tokensFilled`|`uint256`|The amount of tokens claimed|

## Errors
### IDistributionContract__InvalidAmountReceived
Error thrown when the amount received is invalid


```solidity
error IDistributionContract__InvalidAmountReceived();
```

### InvalidAmount
Error thrown when not enough amount is deposited


```solidity
error InvalidAmount();
```

### AuctionNotStarted
Error thrown when the auction is not started


```solidity
error AuctionNotStarted();
```

### FloorPriceIsZero
Error thrown when the floor price is zero


```solidity
error FloorPriceIsZero();
```

### TickSpacingIsZero
Error thrown when the tick spacing is zero


```solidity
error TickSpacingIsZero();
```

### ClaimBlockIsBeforeEndBlock
Error thrown when the claim block is before the end block


```solidity
error ClaimBlockIsBeforeEndBlock();
```

### BidAlreadyExited
Error thrown when the bid has already been exited


```solidity
error BidAlreadyExited();
```

### CannotExitBid
Error thrown when the bid is higher than the clearing price


```solidity
error CannotExitBid();
```

### InvalidCheckpointHint
Error thrown when the checkpoint hint is invalid


```solidity
error InvalidCheckpointHint();
```

### NotClaimable
Error thrown when the bid is not claimable


```solidity
error NotClaimable();
```

### BidNotExited
Error thrown when the bid has not been exited


```solidity
error BidNotExited();
```

### TokenTransferFailed
Error thrown when the token transfer fails


```solidity
error TokenTransferFailed();
```

### AuctionIsNotOver
Error thrown when the auction is not over


```solidity
error AuctionIsNotOver();
```

### InvalidBidPrice
Error thrown when a new bid is less than or equal to the clearing price


```solidity
error InvalidBidPrice();
```

