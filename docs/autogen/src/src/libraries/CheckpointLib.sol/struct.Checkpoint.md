# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/35473874d97222cd9ba85c79c74cfb5935603cd9/src/libraries/CheckpointLib.sol)


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

