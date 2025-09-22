# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/c5718c13b5a20e0aacebf2071a7062f239033bd5/src/libraries/CheckpointLib.sol)


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

