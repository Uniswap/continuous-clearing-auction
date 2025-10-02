# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/0a5b39a6c7a8e647dc0617b7ec4d2db5ff917aa5/src/libraries/CheckpointLib.sol)


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

