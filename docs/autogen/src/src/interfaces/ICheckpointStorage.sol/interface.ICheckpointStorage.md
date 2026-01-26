# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/5b8ed17aad591faad07c06ffc6e4d04217c2094e/src/interfaces/ICheckpointStorage.sol)

Interface for checkpoint storage operations


## Functions
### latestCheckpoint

Get the latest checkpoint at the last checkpointed block

Be aware that the latest checkpoint may not be up to date, it is recommended
to always call `checkpoint()` before using getter functions


```solidity
function latestCheckpoint() external view returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The latest checkpoint|


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


## Errors
### CheckpointBlockNotIncreasing
Revert when attempting to insert a checkpoint at a block number not strictly greater than the last one


```solidity
error CheckpointBlockNotIncreasing();
```

