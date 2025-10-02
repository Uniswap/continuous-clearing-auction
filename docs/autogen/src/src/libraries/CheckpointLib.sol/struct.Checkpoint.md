# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/7481976d9a045c9df236ecc1331ce832ed4d18a0/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7X7 totalClearedX7X7;
    ValueX7X7 cumulativeSupplySoldToClearingPriceX7X7;
    uint256 cumulativeMpsPerPrice;
    uint24 cumulativeMps;
    uint64 prev;
    uint64 next;
}
```

