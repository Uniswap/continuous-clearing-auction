# Auction
[Git Source](https://github.com/Uniswap/twap-auction/blob/d200a5546708f64ff0ca4fc019aad142ca33d228/src/Auction.sol)

**Inherits:**
[BidStorage](/src/BidStorage.sol/abstract.BidStorage.md), [CheckpointStorage](/src/CheckpointStorage.sol/abstract.CheckpointStorage.md), [AuctionStepStorage](/src/AuctionStepStorage.sol/abstract.AuctionStepStorage.md), [TickStorage](/src/TickStorage.sol/abstract.TickStorage.md), [PermitSingleForwarder](/src/PermitSingleForwarder.sol/abstract.PermitSingleForwarder.md), [IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)


## State Variables
### PERMIT2
Permit2 address


```solidity
address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
```


### currency
The currency of the auction


```solidity
Currency public immutable currency;
```


### token
The token of the auction


```solidity
IERC20Minimal public immutable token;
```


### totalSupply
The total supply of token to sell


```solidity
uint256 public immutable totalSupply;
```


### tokensRecipient
The recipient of any unsold tokens


```solidity
address public immutable tokensRecipient;
```


### fundsRecipient
The recipient of the funds from the auction


```solidity
address public immutable fundsRecipient;
```


### claimBlock
The block at which purchased tokens can be claimed


```solidity
uint64 public immutable claimBlock;
```


### validationHook
An optional hook to be called before a bid is registered


```solidity
IValidationHook public immutable validationHook;
```


### sumDemandAboveClearing
The sum of demand in ticks above the clearing price


```solidity
Demand public sumDemandAboveClearing;
```


## Functions
### constructor


```solidity
constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
    AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
    TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
    PermitSingleForwarder(IAllowanceTransfer(PERMIT2));
```

### onTokensReceived

Notify a distribution contract that it has received the tokens to distribute


```solidity
function onTokensReceived() external view;
```

### _advanceToCurrentStep

Advance the current step until the current block is within the step

*The checkpoint must be up to date since `transform` depends on the clearingPrice*


```solidity
function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint256 blockNumber)
    internal
    returns (Checkpoint memory);
```

### _calculateNewClearingPrice

Calculate the new clearing price


```solidity
function _calculateNewClearingPrice(uint256 minimumClearingPrice, uint256 supply) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`minimumClearingPrice`|`uint256`|The minimum clearing price|
|`supply`|`uint256`|The token supply at or above nextActiveTickPrice in the block|


### _unsafeCheckpoint

Internal function for checkpointing at a specific block number


```solidity
function _unsafeCheckpoint(uint256 blockNumber) internal returns (Checkpoint memory _checkpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block number to checkpoint at|


### _getFinalCheckpoint

Return the final checkpoint of the auction

*Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
any future calls to `step.mps` will return the mps of the last step in the auction*


```solidity
function _getFinalCheckpoint() internal returns (Checkpoint memory _checkpoint);
```

### _submitBid


```solidity
function _submitBid(
    uint256 maxPrice,
    bool exactIn,
    uint256 amount,
    address owner,
    uint256 prevTickPrice,
    bytes calldata hookData
) internal returns (uint256 bidId);
```

### _processExit

Given a bid, tokens filled and refund, process the transfers and refund


```solidity
function _processExit(uint256 bidId, Bid memory bid, uint256 tokensFilled, uint256 refund) internal;
```

### checkpoint

Register a new checkpoint

*This function is called every time a new bid is submitted above the current clearing price*


```solidity
function checkpoint() public returns (Checkpoint memory _checkpoint);
```

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
) external payable returns (uint256);
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
|`<none>`|`uint256`|bidId The id of the bid|


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

*Anyone can claim tokens for any bid, the tokens are transferred to the bid owner*


```solidity
function claimTokens(uint256 bidId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


