# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/94b6014be30336d3af58264dcb1a5e840671c7b6/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7 totalCleared;
    ValueX7 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    ValueX7 cumulativeSupplySoldToClearingPrice;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}
```

