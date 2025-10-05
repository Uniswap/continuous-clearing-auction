# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/interfaces/ICheckpointStorage.sol)

Interface for checkpoint storage operations


## Functions
### latestCheckpoint

Get the latest checkpoint at the last checkpointed block


```solidity
function latestCheckpoint() external view returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The latest checkpoint|


### clearingPrice

Get the clearing price at the last checkpointed block


```solidity
function clearingPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The current clearing price|


### currencyRaised

Get the currency raised at the last checkpointed block

*This may be less than the balance of this contract as tokens are sold at different prices*


```solidity
function currencyRaised() external view returns (uint256);
```

### lastCheckpointedBlock

Get the number of the last checkpointed block


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

