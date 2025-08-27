# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/1de405fbc26e1c3a6f5b413734244f9a9fe59e87/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    uint256 blockCleared;
    uint256 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint256 cumulativeMpsPerPrice;
    uint256 sumPartialFillRate;
    uint256 resolvedDemandAboveClearingPrice;
    uint256 prev;
}
```

