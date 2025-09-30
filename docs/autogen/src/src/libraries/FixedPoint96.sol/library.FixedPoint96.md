# FixedPoint96
[Git Source](https://github.com/Uniswap/twap-auction/blob/cfe064d2fdebcf6b4861fcd47553d75e33aa20ae/src/libraries/FixedPoint96.sol)

A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)

*Copied from https://github.com/Uniswap/v4-core/blob/main/src/libraries/FixedPoint96.sol*


## State Variables
### RESOLUTION

```solidity
uint8 internal constant RESOLUTION = 96;
```


### Q96

```solidity
uint256 internal constant Q96 = 0x1000000000000000000000000;
```


