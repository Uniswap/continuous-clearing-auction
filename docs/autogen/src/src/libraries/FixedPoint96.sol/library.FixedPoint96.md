# FixedPoint96
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/FixedPoint96.sol)

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


