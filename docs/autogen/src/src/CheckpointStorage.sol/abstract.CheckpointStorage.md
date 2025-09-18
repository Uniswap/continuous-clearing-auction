# CheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/c484a619b57e8cdba6726e41eefe57b0876affbb/src/CheckpointStorage.sol)

**Inherits:**
[ICheckpointStorage](/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md)

Abstract contract for managing auction checkpoints and bid fill calculations


## State Variables
### MAX_BLOCK_NUMBER

```solidity
uint64 public constant MAX_BLOCK_NUMBER = type(uint64).max;
```


### checkpoints
Storage of checkpoints


```solidity
mapping(uint64 blockNumber => Checkpoint) public checkpoints;
```


### lastCheckpointedBlock
The block number of the last checkpointed block


```solidity
uint64 public lastCheckpointedBlock;
```


## Functions
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

### currencyRaised

Get the currency raised at the last checkpointed block

*This may be less than the balance of this contract as tokens are sold at different prices*


```solidity
function currencyRaised() public view returns (uint256);
```

### _getCheckpoint

Get a checkpoint from storage


```solidity
function _getCheckpoint(uint64 blockNumber) internal view returns (Checkpoint memory);
```

### _insertCheckpoint

Insert a checkpoint into storage

*This function updates the prev and next pointers of the latest checkpoint and the new checkpoint*


```solidity
function _insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) internal;
```

### _accountFullyFilledCheckpoints

Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints

*This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
because it uses lazy accounting to calculate the tokens filled*


```solidity
function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`upper`|`Checkpoint`|The upper checkpoint|
|`startCheckpoint`|`Checkpoint`|The start checkpoint of the bid|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpent`|`uint256`|The amount of currency spent|


### _accountPartiallyFilledCheckpoints

Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price


```solidity
function _accountPartiallyFilledCheckpoints(
    ValueX7 cumulativeSupplySoldToClearingPriceX7,
    ValueX7 bidDemandX7,
    ValueX7 tickDemandX7,
    uint256 bidMaxPrice
) internal pure returns (uint256 tokensFilled, uint256 currencySpent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`cumulativeSupplySoldToClearingPriceX7`|`ValueX7`|The cumulative supply sold to the clearing price|
|`bidDemandX7`|`ValueX7`|The demand of the bid|
|`tickDemandX7`|`ValueX7`|The demand of the tick|
|`bidMaxPrice`|`uint256`|The max price of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpent`|`uint256`|The amount of currency spent|


### _calculateFill

Calculate the tokens filled and currency spent for a bid

*This function uses lazy accounting to efficiently calculate fills across time periods without iterating through individual blocks.
It MUST only be used when the bid's max price is strictly greater than the clearing price throughout the entire period being calculated.*


```solidity
function _calculateFill(Bid memory bid, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|the bid to evaluate|
|`cumulativeMpsPerPriceDelta`|`uint256`|the cumulative sum of supply to price ratio|
|`cumulativeMpsDelta`|`uint24`|the cumulative sum of mps values across the block range|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|the amount of tokens filled for this bid|
|`currencySpent`|`uint256`|the amount of currency spent by this bid|


