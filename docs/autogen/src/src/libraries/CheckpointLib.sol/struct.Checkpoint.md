# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/4a2534467c505f9bb8c4a942d2cc4f01d7d061ef/src/libraries/CheckpointLib.sol)


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

