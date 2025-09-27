# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/d8923ff869bd7fcb722e5bcf182d5585489c9701/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7 totalCleared;
    Demand sumDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    ValueX7 cumulativeSupplySoldToClearingPriceX7;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}
```

