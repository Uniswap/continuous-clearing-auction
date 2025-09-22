# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/0870269de9eb67f838fdf37d31febd27dfdef28a/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7 totalCleared;
    ValueX7 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    ValueX7 cumulativeSupplySoldToClearingPriceX7;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}
```

