# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/cfe064d2fdebcf6b4861fcd47553d75e33aa20ae/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

