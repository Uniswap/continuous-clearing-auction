# ICheckpointStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/4a2534467c505f9bb8c4a942d2cc4f01d7d061ef/src/interfaces/ICheckpointStorage.sol)


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
function currencyRaised() external view returns (uint128);
```

### lastCheckpointedBlock

Get the number of the last checkpointed block


```solidity
function lastCheckpointedBlock() external view returns (uint64);
```

