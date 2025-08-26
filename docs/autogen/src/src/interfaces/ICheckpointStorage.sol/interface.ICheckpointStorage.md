# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/381b0ae668f577856bcecaebacb52bec6c71bf17/src/interfaces/ICheckpointStorage.sol)


## Functions
### latestCheckpoint

Get the latest checkpoint at the last checkpointed block


```solidity
function latestCheckpoint() external view returns (Checkpoint memory);
```

### clearingPrice

Get the clearing price at the last checkpointed block


```solidity
function clearingPrice() external view returns (uint256);
```

### lastCheckpointedBlock

Get the number of the last checkpointed block


```solidity
function lastCheckpointedBlock() external view returns (uint256);
```

