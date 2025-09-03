# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/e6ae006b4d791723cfa088f0c2d93768cc82ee16/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint128 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
    uint128 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    uint256 cumulativeSupplySoldToClearingPrice;
}
```

