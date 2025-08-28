# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/ca9baa0f4ab5e1713f915e16ec913f5984be79da/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint128 blockCleared;
    uint128 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
    uint128 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    uint256 cumulativeSupplySoldToClearingPrice;
    uint256 resolvedDemandAboveClearingPrice;
    uint64 prev;
    uint64 next;
}
```

