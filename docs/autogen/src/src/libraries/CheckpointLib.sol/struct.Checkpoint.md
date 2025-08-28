# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/579dd192cb3d6db3d93e95ab513fff830b038a4e/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint256 blockCleared;
    uint256 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint256 cumulativeMpsPerPrice;
    uint256 sumPartialFillRate;
    uint256 resolvedDemandAboveClearingPrice;
    uint64 prev;
    uint64 next;
}
```

