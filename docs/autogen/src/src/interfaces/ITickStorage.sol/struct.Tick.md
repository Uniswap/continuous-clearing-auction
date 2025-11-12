# Tick
[Git Source](https://github.com/Uniswap/twap-auction/blob/ab88be10ec09bebb9ce21e524c265366917b5a1f/src/interfaces/ITickStorage.sol)

Each tick contains a pointer to the next price in the linked list
and the cumulative currency demand at the tick's price level


```solidity
struct Tick {
uint256 next;
uint256 currencyDemandQ96;
}
```

