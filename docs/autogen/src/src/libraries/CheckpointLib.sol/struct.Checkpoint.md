# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/93c0c780ed33d07191c07fe0752db1c29bbcb8f7/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
    uint256 clearingPrice;
    ValueX7 currencyRaisedAtClearingPriceQ96_X7;
    uint256 cumulativeMpsPerPrice;
    uint24 cumulativeMps;
    uint64 prev;
    uint64 next;
}
```

