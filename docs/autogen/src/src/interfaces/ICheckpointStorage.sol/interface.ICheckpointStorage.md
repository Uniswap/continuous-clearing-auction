# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/97b9f50fc290e1d145d29832b96438e6ecfe03de/src/interfaces/ICheckpointStorage.sol)


## Functions
### latestCheckpoint

Get the latest checkpoint at the last checkpointed block

*This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.*


```solidity
function latestCheckpoint() external view returns (Checkpoint memory);
```

### clearingPrice

Get the clearing price at the last checkpointed block

*This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.*


```solidity
function clearingPrice() external view returns (uint256);
```

### currencyRaised

Get the currency raised at the last checkpointed block

*This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.*

*This also may be less than the balance of this contract as tokens are sold at different prices.*


```solidity
function currencyRaised() external view returns (uint256);
```

### lastCheckpointedBlock

Get the number of the last checkpointed block

*This may be out of date and not reflect the latest state of the auction. As a best practice, always call `checkpoint()` beforehand.*


```solidity
function lastCheckpointedBlock() external view returns (uint64);
```

### getCheckpoint

Get a checkpoint at a block number

*The returned checkpoint may not exist if the block was never checkpointed*


```solidity
function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint64`|The block number of the checkpoint to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|checkpoint The checkpoint at the block number|


