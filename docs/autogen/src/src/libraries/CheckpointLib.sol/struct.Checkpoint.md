# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint256 blockCleared;
    uint256 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint256 cumulativeMpsPerPrice;
    uint256 resolvedDemandAboveClearingPrice;
    uint256 prev;
}
```

