# FixedPoint96
[Git Source](https://github.com/Uniswap/twap-auction/blob/f4ca3ef3995c04dfc87924fa2a7301b4b6eb60a2/src/libraries/FixedPoint96.sol)

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


