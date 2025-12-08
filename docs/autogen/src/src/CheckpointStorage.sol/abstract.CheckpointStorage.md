# CheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/CheckpointStorage.sol)

**Inherits:**
[ICheckpointStorage](/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md)

**Title:**
CheckpointStorage

Abstract contract for managing auction checkpoints and bid fill calculations


## State Variables
### MAX_BLOCK_NUMBER
Maximum block number value used as sentinel for last checkpoint


```solidity
uint64 public constant MAX_BLOCK_NUMBER = type(uint64).max
```


### $_checkpoints
Storage of checkpoints


```solidity
mapping(uint64 blockNumber => Checkpoint) private $_checkpoints
```


### $lastCheckpointedBlock
The block number of the last checkpointed block


```solidity
uint64 internal $lastCheckpointedBlock
```


## Functions
### latestCheckpoint

Get the latest checkpoint at the last checkpointed block

Be aware that the latest checkpoint may not be up to date, it is recommended
to always call `checkpoint()` before using getter functions


```solidity
function latestCheckpoint() public view returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The latest checkpoint|


### clearingPrice

Get the clearing price at the last checkpointed block

Be aware that the latest checkpoint may not be up to date, it is recommended
to always call `checkpoint()` before using getter functions


```solidity
function clearingPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The current clearing price in Q96 form|


### _getCheckpoint

Get a checkpoint from storage


```solidity
function _getCheckpoint(uint64 blockNumber) internal view returns (Checkpoint memory);
```

### _insertCheckpoint

Insert a checkpoint into storage

This function updates the prev and next pointers of the latest checkpoint and the new checkpoint


```solidity
function _insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) internal;
```

### _accountFullyFilledCheckpoints

Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints

This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
because it uses lazy accounting to calculate the tokens filled


```solidity
function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpentQ96);
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
|`currencySpentQ96`|`uint256`|The amount of currency spent in Q96 form|


### _accountPartiallyFilledCheckpoints

Calculate the tokens sold and currency spent for a partially filled bid


```solidity
function _accountPartiallyFilledCheckpoints(
    Bid memory bid,
    uint256 tickDemandQ96,
    ValueX7 currencyRaisedAtClearingPriceQ96_X7
) internal pure returns (uint256 tokensFilled, uint256 currencySpentQ96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|
|`tickDemandQ96`|`uint256`|The total demand at the tick|
|`currencyRaisedAtClearingPriceQ96_X7`|`ValueX7`|The cumulative supply sold to the clearing price|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpentQ96`|`uint256`|The amount of currency spent in Q96 form|


### lastCheckpointedBlock

Get the number of the last checkpointed block

Be aware that the last checkpointed block may not be up to date, it is recommended
to always call `checkpoint()` before using getter functions


```solidity
function lastCheckpointedBlock() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The block number of the last checkpoint|


### checkpoints

Get a checkpoint at a block number


```solidity
function checkpoints(uint64 blockNumber) external view returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint64`|The block number to get the checkpoint for|


