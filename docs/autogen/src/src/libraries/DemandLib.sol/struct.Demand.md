# Demand
[Git Source](https://github.com/Uniswap/twap-auction/blob/45bab3c8875b0df2a6d4a56c26add6ec4f6a45f5/src/libraries/DemandLib.sol)

Struct containing currency demand and token demand

*All values are in ValueX7 format*


```solidity
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}
```

