# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/53d58176f6e0d9cd2a209fdc23933a60c6638f06/src/libraries/CheckpointLib.sol)


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

