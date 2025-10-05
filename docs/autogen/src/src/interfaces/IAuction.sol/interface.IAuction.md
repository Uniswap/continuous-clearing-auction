# IAuction
[Git Source](https://github.com/Uniswap/twap-auction/blob/8c2930146e31b54e368caa772ec5bb20d1a47d12/src/interfaces/IAuction.sol)

**Inherits:**
[IDistributionContract](/src/interfaces/external/IDistributionContract.sol/interface.IDistributionContract.md), [ICheckpointStorage](/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md), [ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md), [IAuctionStepStorage](/src/interfaces/IAuctionStepStorage.sol/interface.IAuctionStepStorage.md), [ITokenCurrencyStorage](/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md), [IBidStorage](/src/interfaces/IBidStorage.sol/interface.IBidStorage.md)

Interface for the Auction contract


## Functions
### submitBid

Submit a new bid


```solidity
function submitBid(uint256 maxPrice, uint256 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
    external
    payable
    returns (uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint256`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`prevTickPrice`|`uint256`|The price of the previous tick|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### submitBid

Submit a new bid without specifying the previous tick price

*It is NOT recommended to use this function unless you are sure that `maxPrice` is already initialized
as this function will iterate through every tick starting from the floor price if it is not.*


```solidity
function submitBid(uint256 maxPrice, uint256 amount, address owner, bytes calldata hookData)
    external
    payable
    returns (uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint256`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### checkpoint

Register a new checkpoint

*This function is called every time a new bid is submitted above the current clearing price*

*If the auction is over, it returns the final checkpoint*


```solidity
function checkpoint() external returns (Checkpoint memory _checkpoint);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint at the current block|


### isGraduated

Whether the auction has graduated as of the given checkpoint

*The auction is considered `graudated` if the clearing price is greater than the floor price
since that means it has sold all of the total supply of tokens.*

*Be aware that the latest checkpoint may be out of date*


```solidity
function isGraduated() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the auction has graduated, false otherwise|


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

*Can be called by anyone after the auction has ended*


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

### sumCurrencyDemandAboveClearingX7

The sum of demand in ticks above the clearing price


```solidity
function sumCurrencyDemandAboveClearingX7() external view returns (ValueX7);
```

## Events
### TokensReceived
Emitted when the tokens are received


```solidity
event TokensReceived(uint256 totalSupply);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`totalSupply`|`uint256`|The total supply of tokens received|

### BidSubmitted
Emitted when a bid is submitted


```solidity
event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|
|`price`|`uint256`|The price of the bid|
|`amount`|`uint256`|The amount of the bid|

### CheckpointUpdated
Emitted when a new checkpoint is created


```solidity
event CheckpointUpdated(
    uint256 indexed blockNumber, uint256 clearingPrice, ValueX7X7 totalClearedX7X7, uint24 cumulativeMps
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number of the checkpoint|
|`clearingPrice`|`uint256`|The clearing price of the checkpoint|
|`totalClearedX7X7`|`ValueX7X7`|The total amount of tokens cleared|
|`cumulativeMps`|`uint24`|The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)|

### ClearingPriceUpdated
Emitted when the clearing price is updated


```solidity
event ClearingPriceUpdated(uint256 indexed blockNumber, uint256 clearingPrice);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`||
|`clearingPrice`|`uint256`|The new clearing price|

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
### InvalidTokenAmountReceived
Error thrown when the amount received is invalid


```solidity
error InvalidTokenAmountReceived();
```

### InvalidAmount
Error thrown when not enough amount is deposited


```solidity
error InvalidAmount();
```

### CurrencyIsNotNative
Error thrown when msg.value is non zero when currency is not ETH


```solidity
error CurrencyIsNotNative();
```

### AuctionNotStarted
Error thrown when the auction is not started


```solidity
error AuctionNotStarted();
```

### TokensNotReceived
Error thrown when the tokens required for the auction have not been received


```solidity
error TokensNotReceived();
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

### CannotPartiallyExitBidBeforeEndBlock
Error thrown when the bid cannot be partially exited before the end block


```solidity
error CannotPartiallyExitBidBeforeEndBlock();
```

### InvalidLastFullyFilledCheckpointHint
Error thrown when the last fully filled checkpoint hint is invalid


```solidity
error InvalidLastFullyFilledCheckpointHint();
```

### InvalidOutbidBlockCheckpointHint
Error thrown when the outbid block checkpoint hint is invalid


```solidity
error InvalidOutbidBlockCheckpointHint();
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

### InvalidBidUnableToClear
Error thrown when the bid is too large


```solidity
error InvalidBidUnableToClear();
```

### AuctionSoldOut
Error thrown when the auction has sold the entire total supply of tokens


```solidity
error AuctionSoldOut();
```

