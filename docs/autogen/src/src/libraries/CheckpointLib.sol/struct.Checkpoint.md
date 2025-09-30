# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/6199a07349a5d22f79f49db95ea478090bd8c68d/src/libraries/CheckpointLib.sol)


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

