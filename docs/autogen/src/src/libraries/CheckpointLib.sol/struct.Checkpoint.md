# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/88477dc12ad46ab8c9c67c45a4c065f7cc42fc7e/src/libraries/CheckpointLib.sol)


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

