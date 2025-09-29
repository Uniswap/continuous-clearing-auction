# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/07712f11fafad883cb4261b09b8cf07d1b82d868/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7X7 totalClearedX7X7;
    ValueX7X7 cumulativeSupplySoldToClearingPriceX7X7;
    Demand sumDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}
```

