# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/3ae5c7802ad9830c8939d6dbff65ade7ca715a97/src/libraries/CheckpointLib.sol)


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
}
```

