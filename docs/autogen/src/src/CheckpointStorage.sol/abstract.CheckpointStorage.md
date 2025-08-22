# CheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/CheckpointStorage.sol)

**Inherits:**
[TickStorage](/src/TickStorage.sol/abstract.TickStorage.md)

Abstract contract for managing auction checkpoints and bid fill calculations


## State Variables
### floorPrice
The starting price of the auction


```solidity
uint256 public immutable floorPrice;
```


### checkpoints
Storage of checkpoints


```solidity
mapping(uint256 blockNumber => Checkpoint) private checkpoints;
```


### lastCheckpointedBlock
The block number of the last checkpointed block


```solidity
uint256 public lastCheckpointedBlock;
```


## Functions
### constructor


```solidity
constructor(uint256 _floorPrice, uint256 _tickSpacing) TickStorage(_tickSpacing, _floorPrice);
```

### latestCheckpoint

Get the latest checkpoint at the last checkpointed block


```solidity
function latestCheckpoint() public view returns (Checkpoint memory);
```

### clearingPrice

Get the clearing price at the last checkpointed block


```solidity
function clearingPrice() public view returns (uint256);
```

### _getCheckpoint

Get a checkpoint from storage


```solidity
function _getCheckpoint(uint256 blockNumber) internal view returns (Checkpoint memory);
```

### _insertCheckpoint

Insert a checkpoint into storage


```solidity
function _insertCheckpoint(Checkpoint memory checkpoint) internal;
```

### _updateCheckpoint

Update the checkpoint


```solidity
function _updateCheckpoint(
    Checkpoint memory _checkpoint,
    AuctionStep memory _step,
    Demand memory _sumDemandAboveClearing,
    uint256 _newClearingPrice,
    uint256 _blockTokenSupply
) internal view returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint to update|
|`_step`|`AuctionStep`||
|`_sumDemandAboveClearing`|`Demand`|The sum of demand above the clearing price|
|`_newClearingPrice`|`uint256`|The new clearing price|
|`_blockTokenSupply`|`uint256`|The token supply at or above tickUpper in the block|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The updated checkpoint|


### _accountFullyFilledCheckpoints

Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints

*This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
because it uses lazy accounting to calculate the tokens filled*


```solidity
function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory lower, Bid memory bid)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`upper`|`Checkpoint`|The upper checkpoint|
|`lower`|`Checkpoint`|The lower checkpoint|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpent`|`uint256`|The amount of currency spent|


### _accountPartiallyFilledCheckpoints

Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price

*This function does an iterative search through the checkpoints and thus is more gas intensive*


```solidity
function _accountPartiallyFilledCheckpoints(Checkpoint memory lastValidCheckpoint, Bid memory bid)
    internal
    view
    returns (uint256 tokensFilled, uint256 currencySpent, uint256 nextCheckpointBlock);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lastValidCheckpoint`|`Checkpoint`|The last checkpoint where the clearing price is == bid.maxPrice|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpent`|`uint256`|The amount of currency spent|
|`nextCheckpointBlock`|`uint256`|The block number of the checkpoint under the bid's max price. Will be 0 if it does not exist.|


### _calculateFill

Calculate the tokens filled and currency spent for a bid

*This function uses lazy accounting to efficiently calculate fills across time periods without iterating through individual blocks.
It MUST only be used when the bid's max price is strictly greater than the clearing price throughout the entire period being calculated.*


```solidity
function _calculateFill(
    Bid memory bid,
    uint256 cumulativeMpsPerPriceDelta,
    uint24 cumulativeMpsDelta,
    uint24 mpsDenominator
) internal pure returns (uint256 tokensFilled, uint256 currencySpent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|the bid to evaluate|
|`cumulativeMpsPerPriceDelta`|`uint256`|the cumulative sum of supply to price ratio|
|`cumulativeMpsDelta`|`uint24`|the cumulative sum of mps values across the block range|
|`mpsDenominator`|`uint24`|the percentage of the auction which the bid was spread over|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|the amount of tokens filled for this bid|
|`currencySpent`|`uint256`|the amount of currency spent by this bid|


### _calculatePartialFill

Calculate the tokens filled and proportion of input used for a partially filled bid


```solidity
function _calculatePartialFill(
    uint256 bidDemand,
    uint256 tickDemand,
    uint256 price,
    uint256 supplyOverMps,
    uint24 mpsDelta,
    uint256 resolvedDemandAboveClearingPrice
) internal pure returns (uint256 tokensFilled, uint256 currencySpent);
```

