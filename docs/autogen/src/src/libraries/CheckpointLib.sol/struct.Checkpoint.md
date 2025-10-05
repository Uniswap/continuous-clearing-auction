# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/3c95f1e080149f3b4149fa29f3305216cb44fbf5/src/libraries/CheckpointLib.sol)


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

