# ConstantsLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/68d18000c60b2a641f136e527165de89b151504d/src/libraries/ConstantsLib.sol)

Library containing protocol constants


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 constant MPS = 1e7;
```


### X7X7_UPPER_BOUND
The upper bound of a ValueX7X7 value


```solidity
uint256 constant X7X7_UPPER_BOUND = (type(uint256).max) / 1e14;
```


### X7_UPPER_BOUND
The upper bound of a ValueX7 value


```solidity
uint256 constant X7_UPPER_BOUND = (type(uint256).max) / 1e7;
```


