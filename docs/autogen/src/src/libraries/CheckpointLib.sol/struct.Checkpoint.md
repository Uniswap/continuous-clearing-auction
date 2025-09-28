# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/0ee04bc2c45f6d51f37030260f300f404e183bf7/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint128 totalCleared;
    uint128 resolvedDemandAboveClearingPrice;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
    uint256 cumulativeMpsPerPrice;
    uint256 cumulativeSupplySoldToClearingPrice;
}
```

