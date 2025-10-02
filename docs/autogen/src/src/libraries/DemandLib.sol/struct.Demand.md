# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/f4ca3ef3995c04dfc87924fa2a7301b4b6eb60a2/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

