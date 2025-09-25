# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/f80ba18b60de4b770005741879dfdddb0bfb58e3/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

