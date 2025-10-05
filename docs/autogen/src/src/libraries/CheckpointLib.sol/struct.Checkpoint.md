# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/ae5ec627b376e2746e108bdb684105b8397d2234/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7X7 totalCurrencyRaisedX7X7;
    ValueX7X7 cumulativeCurrencyRaisedAtClearingPriceX7X7;
    uint256 cumulativeMpsPerPrice;
    uint24 cumulativeMps;
    uint64 prev;
    uint64 next;
}
```

