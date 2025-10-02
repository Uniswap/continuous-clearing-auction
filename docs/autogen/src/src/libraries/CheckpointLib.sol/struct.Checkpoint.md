# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/4e79543472823ca4f19066f04f5392aba6563627/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7X7 totalClearedX7X7;
    ValueX7X7 cumulativeSupplySoldToClearingPriceX7X7;
    uint256 cumulativeMpsPerPrice;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}
```

