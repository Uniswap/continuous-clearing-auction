# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/f53d7155325c22ef28d878c4d9443735141b48d7/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

