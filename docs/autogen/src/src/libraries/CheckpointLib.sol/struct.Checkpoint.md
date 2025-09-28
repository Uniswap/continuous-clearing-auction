# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/ace0c8fa02a7f9ecc269c8d6adca532a0d0858dc/src/libraries/CheckpointLib.sol)


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

