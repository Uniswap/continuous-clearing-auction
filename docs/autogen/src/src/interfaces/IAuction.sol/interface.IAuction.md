# IAuction
[Git Source](https://github.com/Uniswap/twap-auction/blob/d200a5546708f64ff0ca4fc019aad142ca33d228/src/interfaces/IAuction.sol)

**Inherits:**
[IDistributionContract](/src/interfaces/external/IDistributionContract.sol/interface.IDistributionContract.md), [ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md), [IAuctionStepStorage](/src/interfaces/IAuctionStepStorage.sol/interface.IAuctionStepStorage.md)

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

*This function can only be used for bids where the max price is below the final clearing price*


```solidity
function exitPartiallyFilledBid(uint256 bidId, uint256 outbidCheckpointBlock) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`outbidCheckpointBlock`|`uint256`|The block of the first checkpoint where the clearing price is strictly > bid.maxPrice|


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
event CheckpointUpdated(uint256 indexed blockNumber, uint256 clearingPrice, uint256 totalCleared, uint24 cumulativeMps);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number of the checkpoint|
|`clearingPrice`|`uint256`|The clearing price of the checkpoint|
|`totalCleared`|`uint256`|The total amount of tokens cleared|
|`cumulativeMps`|`uint24`|The cumulative percentage of total tokens allocated across all previous steps, represented in ten-millionths of the total supply (1e7 = 100%)|

### BidExited
Emitted when a bid is exited


```solidity
event BidExited(uint256 indexed bidId, address indexed owner);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`owner`|`address`|The owner of the bid|

### TokensClaimed
Emitted when a bid is claimed


```solidity
event TokensClaimed(address indexed owner, uint256 tokensFilled);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner of the bid|
|`tokensFilled`|`uint256`|The amount of tokens claimed|

## Errors
### IDistributionContract__InvalidToken
Error thrown when the token is invalid


```solidity
error IDistributionContract__InvalidToken();
```

### IDistributionContract__InvalidAmount
Error thrown when the amount is invalid


```solidity
error IDistributionContract__InvalidAmount();
```

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

### TotalSupplyIsZero
Error thrown when the total supply is zero


```solidity
error TotalSupplyIsZero();
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

### FundsRecipientIsZero
Error thrown when the funds recipient is the zero address


```solidity
error FundsRecipientIsZero();
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

### InvalidBidPrice
Error thrown when the bid price is invalid


```solidity
error InvalidBidPrice();
```

