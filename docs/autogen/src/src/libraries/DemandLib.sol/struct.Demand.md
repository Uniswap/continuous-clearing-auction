# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/d2fa994e75f232a6bfe496080d6fadb2906a187d/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

