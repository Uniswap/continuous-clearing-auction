# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/eddb06d9f9e6a95363d90d7326e355d98c8b0712/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

