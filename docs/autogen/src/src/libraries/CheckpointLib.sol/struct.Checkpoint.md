# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/2ab6f1f651f977062136e0144a4f3e636a17d226/src/libraries/CheckpointLib.sol)


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

