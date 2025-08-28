# Auction
[Git Source](https://github.com/Uniswap/twap-auction/blob/c80b693e5a5d33e8f82791abf78b3e8a0e078948/src/Auction.sol)

**Inherits:**
[BidStorage](/src/BidStorage.sol/abstract.BidStorage.md), [CheckpointStorage](/src/CheckpointStorage.sol/abstract.CheckpointStorage.md), [AuctionStepStorage](/src/AuctionStepStorage.sol/abstract.AuctionStepStorage.md), [TickStorage](/src/TickStorage.sol/abstract.TickStorage.md), [PermitSingleForwarder](/src/PermitSingleForwarder.sol/abstract.PermitSingleForwarder.md), [TokenCurrencyStorage](/src/TokenCurrencyStorage.sol/abstract.TokenCurrencyStorage.md), [IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)


## State Variables
### PERMIT2
Permit2 address


```solidity
address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
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
    TokenCurrencyStorage(
        _token,
        _parameters.currency,
        _totalSupply,
        _parameters.tokensRecipient,
        _parameters.fundsRecipient,
        _parameters.graduationThresholdMps,
        _parameters.fundsRecipientData
    )
    TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
    PermitSingleForwarder(IAllowanceTransfer(PERMIT2));
```

### onlyAfterAuctionIsOver

Modifier for functions which can only be called after the auction is over


```solidity
modifier onlyAfterAuctionIsOver();
```

### onTokensReceived

Notify a distribution contract that it has received the tokens to distribute


```solidity
function onTokensReceived() external view;
```

### isGraduated

Whether the auction has graduated as of the latest checkpoint (sold more than the graduation threshold)


```solidity
function isGraduated() public view returns (bool);
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

Calculate the new clearing price, given:


```solidity
function _calculateNewClearingPrice(
    Demand memory blockSumDemandAboveClearing,
    uint256 minimumClearingPrice,
    uint256 supply
) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockSumDemandAboveClearing`|`Demand`|The demand above the clearing price in the block|
|`minimumClearingPrice`|`uint256`|The minimum clearing price|
|`supply`|`uint256`|The token supply at or above nextActiveTickPrice in the block|


### _updateLatestCheckpointToCurrentStep

Update the latest checkpoint to the current step

*This updates the state of the auction accounting for the bids placed after the last checkpoint*


```solidity
function _updateLatestCheckpointToCurrentStep(uint256 blockNumber) internal returns (Checkpoint memory);
```

### _unsafeCheckpoint

Internal function for checkpointing at a specific block number


```solidity
function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint64`|The block number to checkpoint at|


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

*Bids can be submitted anytime between the startBlock and the endBlock.*


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
function exitBid(uint256 bidId) external onlyAfterAuctionIsOver;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### exitPartiallyFilledBid

Exit a bid which has been partially filled

*This function can be used for fully filled or partially filled bids. For fully filled bids, `exitBid` is more efficient*


```solidity
function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 firstOutbidCheckpointBlock)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`lastFullyFilledCheckpointBlock`|`uint64`|The last checkpointed block where the clearing price is strictly < bid.maxPrice|
|`firstOutbidCheckpointBlock`|`uint64`|The first checkpointed block where the clearing price is strictly > bid.maxPrice this value is not required if the bid is partially filled at the end of the auction (final clearing price == bid.maxPrice) if the bid is fully filled at the end of the auction, it should be set to 0|


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


### sweepCurrency

Withdraw all of the currency raised

*Can only be called by the funds recipient after the auction has ended
Must be called before the `claimBlock`*


```solidity
function sweepCurrency() external onlyAfterAuctionIsOver;
```

### sweepUnsoldTokens

Sweep any leftover tokens to the tokens recipient

*This function can only be called after the auction has ended*


```solidity
function sweepUnsoldTokens() external onlyAfterAuctionIsOver;
```

