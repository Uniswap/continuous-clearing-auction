# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/1a7f98b9e1cb9ed630b15a7f62d113994de8c338/src/libraries/CheckpointLib.sol)


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

