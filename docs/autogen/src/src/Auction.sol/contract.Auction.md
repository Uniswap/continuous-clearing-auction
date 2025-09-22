# Auction
[Git Source](https://github.com/Uniswap/twap-auction/blob/f66249e6bb5ebf3be6698edff5f27719f8f33c6e/src/Auction.sol)

**Inherits:**
[BidStorage](/src/BidStorage.sol/abstract.BidStorage.md), [CheckpointStorage](/src/CheckpointStorage.sol/abstract.CheckpointStorage.md), [AuctionStepStorage](/src/AuctionStepStorage.sol/abstract.AuctionStepStorage.md), [TickStorage](/src/TickStorage.sol/abstract.TickStorage.md), [PermitSingleForwarder](/src/PermitSingleForwarder.sol/abstract.PermitSingleForwarder.md), [TokenCurrencyStorage](/src/TokenCurrencyStorage.sol/abstract.TokenCurrencyStorage.md), [IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)

Implements a time weighted uniform clearing price auction

*Can be constructed directly or through the AuctionFactory. In either case, users must validate
that the auction parameters are correct and it has sufficient token balance.*


## State Variables
### PERMIT2
Permit2 address


```solidity
address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
```


### CLAIM_BLOCK
The block at which purchased tokens can be claimed


```solidity
uint64 internal immutable CLAIM_BLOCK;
```


### VALIDATION_HOOK
An optional hook to be called before a bid is registered


```solidity
IValidationHook internal immutable VALIDATION_HOOK;
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
        _parameters.graduationThresholdMps
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

### _transformCheckpoint

Return a new checkpoint after advancing the current checkpoint by some `mps`
This function updates the cumulative values of the checkpoint, requiring that
`clearingPrice` is up to to date


```solidity
function _transformCheckpoint(Checkpoint memory _checkpoint, uint24 deltaMps)
    internal
    view
    returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint to transform|
|`deltaMps`|`uint24`|The number of mps to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The transformed checkpoint|


### _advanceToCurrentStep

Advance the current step until the current block is within the step

*The checkpoint must be up to date since `transform` depends on the clearingPrice*


```solidity
function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint64 blockNumber)
    internal
    returns (Checkpoint memory);
```

### _calculateNewClearingPrice

Calculate the new clearing price, given:


```solidity
function _calculateNewClearingPrice(
    Demand memory blockSumDemandAboveClearing,
    uint256 minimumClearingPrice,
    ValueX7 supplyX7
) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockSumDemandAboveClearing`|`Demand`|The demand above the clearing price in the block|
|`minimumClearingPrice`|`uint256`|The minimum clearing price|
|`supplyX7`|`ValueX7`|The token supply (as ValueX7) at or above nextActiveTickPrice in the block|


### _updateLatestCheckpointToCurrentStep

Update the latest checkpoint to the current step

*This updates the state of the auction accounting for the bids placed after the last checkpoint
Checkpoints are created at the top of each block with a new bid and does NOT include that bid
Because of this, we need to calculate what the new state of the Auction should be before updating
purely on the supply we will sell to the potentially updated `sumDemandAboveClearing` value
After the checkpoint is made up to date we can use those values to update the cumulative values
depending on how much time has passed since the last checkpoint*


```solidity
function _updateLatestCheckpointToCurrentStep(uint64 blockNumber) internal returns (Checkpoint memory);
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

### claimBlock

The block at which the auction can be claimed


```solidity
function claimBlock() external view override(IAuction) returns (uint64);
```

### validationHook

The address of the validation hook for the auction


```solidity
function validationHook() external view override(IAuction) returns (IValidationHook);
```

