# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/046dab769f5d2ea2e8b9bef5d784a4e50afa7ccd/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

