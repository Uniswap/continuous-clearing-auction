# IContinuousClearingAuction
[Git Source](https://github.com/Uniswap/twap-auction/blob/2d1f484976971780a7d5c3026e11b7b066ca6758/src/interfaces/IContinuousClearingAuction.sol)

**Inherits:**
[IDistributionContract](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/external/IDistributionContract.sol/interface.IDistributionContract.md), [ICheckpointStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md), [ITickStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/ITickStorage.sol/interface.ITickStorage.md), [IStepStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/IStepStorage.sol/interface.IStepStorage.md), [ITokenCurrencyStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md), [IBidStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/IBidStorage.sol/interface.IBidStorage.md)

Interface for the ContinuousClearingAuction contract


## Functions
### submitBid

Submit a new bid


```solidity
function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
    external
    payable
    returns (uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`prevTickPrice`|`uint256`|The price of the previous tick|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### submitBid

Submit a new bid without specifying the previous tick price

It is NOT recommended to use this function unless you are sure that `maxPrice` is already initialized
as this function will iterate through every tick starting from the floor price if it is not.


```solidity
function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
    external
    payable
    returns (uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### checkpoint

Register a new checkpoint

This function is called every time a new bid is submitted above the current clearing price

If the auction is over, it returns the final checkpoint


```solidity
function checkpoint() external returns (Checkpoint memory _checkpoint);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint at the current block|


### isGraduated

Whether the auction has graduated as of the given checkpoint

The auction is considered `graudated` if the total currency raised exceeds the required currency raised

Be aware that the latest checkpoint may be out of date


```solidity
function isGraduated() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the auction has graduated, false otherwise|


### currencyRaised

Get the currency raised at the last checkpointed block

This may be less than the balance of this contract if there are outstanding refunds for bidders

Be aware that the latest checkpoint may be out of date


```solidity
function currencyRaised() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The currency raised|


### exitBid

Exit a bid

This function can only be used for bids where the max price is above the final clearing price after the auction has ended


```solidity
function exitBid(uint256 bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### exitPartiallyFilledBid

Exit a bid which has been partially filled

This function can be used only for partially filled bids. For fully filled bids, `exitBid` must be used


```solidity
function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 outbidBlock) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`lastFullyFilledCheckpointBlock`|`uint64`|The last checkpointed block where the clearing price is strictly < bid.maxPrice|
|`outbidBlock`|`uint64`|The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction|


### claimTokens

Claim tokens after the auction's claim block

The bid must be exited before claiming tokens

Anyone can claim tokens for any bid, the tokens are transferred to the bid owner


```solidity
function claimTokens(uint256 bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### claimTokensBatch

Claim tokens for multiple bids

Anyone can claim tokens for bids of the same owner, the tokens are transferred to the owner

A TokensClaimed event is emitted for each bid but only one token transfer will be made


```solidity
function claimTokensBatch(address owner, uint256[] calldata bidIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner of the bids|
|`bidIds`|`uint256[]`|The ids of the bids|


### sweepCurrency

Withdraw all of the currency raised

Can be called by anyone after the auction has ended


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

This function can only be called after the auction has ended


```solidity
function sweepUnsoldTokens() external;
```

### currencyRaisedQ96_X7

The currency raised as of the last checkpoint


```solidity
function currencyRaisedQ96_X7() external view returns (ValueX7);
```

### sumCurrencyDemandAboveClearingQ96

The sum of demand in ticks above the clearing price


```solidity
function sumCurrencyDemandAboveClearingQ96() external view returns (uint256);
```

### totalClearedQ96_X7

The total currency raised as of the last checkpoint


```solidity
function totalClearedQ96_X7() external view returns (ValueX7);
```

### totalCleared

The total tokens cleared as of the last checkpoint in uint256 representation


```solidity
function totalCleared() external view returns (uint256);
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
event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, uint128 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|
|`price`|`uint256`|The price of the bid|
|`amount`|`uint128`|The amount of the bid|

### CheckpointUpdated
Emitted when a new checkpoint is created


```solidity
event CheckpointUpdated(uint256 blockNumber, uint256 clearingPrice, uint24 cumulativeMps);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number of the checkpoint|
|`clearingPrice`|`uint256`|The clearing price of the checkpoint|
|`cumulativeMps`|`uint24`|The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)|

### ClearingPriceUpdated
Emitted when the clearing price is updated


```solidity
event ClearingPriceUpdated(uint256 blockNumber, uint256 clearingPrice);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number when the clearing price was updated|
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

### BidOwnerCannotBeZeroAddress
Error thrown when the bid owner is the zero address


```solidity
error BidOwnerCannotBeZeroAddress();
```

### BidMustBeAboveClearingPrice
Error thrown when the bid price is below the clearing price


```solidity
error BidMustBeAboveClearingPrice();
```

### InvalidBidPriceTooHigh
Error thrown when the bid price is too high given the auction's total supply


```solidity
error InvalidBidPriceTooHigh();
```

### BidAmountTooSmall
Error thrown when the bid amount is too small


```solidity
error BidAmountTooSmall();
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

### FloorPriceAndTickSpacingGreaterThanMaxBidPrice
Error thrown when the floor price plus tick spacing is greater than the maximum bid price


```solidity
error FloorPriceAndTickSpacingGreaterThanMaxBidPrice(uint256 nextTick, uint256 maxBidPrice);
```

### FloorPriceAndTickSpacingTooLarge
Error thrown when the floor price plus tick spacing would overflow a uint256


```solidity
error FloorPriceAndTickSpacingTooLarge();
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

### BatchClaimDifferentOwner
Error thrown when the bids are not owned by the same owner


```solidity
error BatchClaimDifferentOwner(address expectedOwner, address receivedOwner);
```

### BidNotExited
Error thrown when the bid has not been exited


```solidity
error BidNotExited();
```

### CannotPartiallyExitBidBeforeGraduation
Error thrown when the bid cannot be partially exited before the auction has graduated


```solidity
error CannotPartiallyExitBidBeforeGraduation();
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

