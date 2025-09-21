# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/89f9182c5a4250ce7345e6305d6fe12fceb138f4/src/interfaces/ICheckpointStorage.sol)


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

