# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/3f93841df89124f8b3dcf887da46cb2c78bfe137/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

