# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/f11ce57b69e74f06aead0215b40a74eaf1477170/src/libraries/CheckpointLib.sol)


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

