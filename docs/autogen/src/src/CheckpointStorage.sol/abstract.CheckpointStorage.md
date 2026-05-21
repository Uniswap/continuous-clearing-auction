# CheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/c9923b6612650531d4151de2f459778059410469/src/CheckpointStorage.sol)

**Inherits:**
[ICheckpointStorage](/src/interfaces/ICheckpointStorage.sol/interface.ICheckpointStorage.md)

**Title:**
CheckpointStorage

Abstract contract for managing auction checkpoints


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


