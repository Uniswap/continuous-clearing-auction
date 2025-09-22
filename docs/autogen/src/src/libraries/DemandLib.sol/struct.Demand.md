# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/9947ebc29ae68f1eff00f7c7cabe2dd5389ebcb1/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

