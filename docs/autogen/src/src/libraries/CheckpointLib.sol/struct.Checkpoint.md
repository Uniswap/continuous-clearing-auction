# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/91c505699ed85a7d0194c9a8cabc334c99e11f9f/src/libraries/CheckpointLib.sol)


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

