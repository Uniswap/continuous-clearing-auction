# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/eddb06d9f9e6a95363d90d7326e355d98c8b0712/src/libraries/CheckpointLib.sol)


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

