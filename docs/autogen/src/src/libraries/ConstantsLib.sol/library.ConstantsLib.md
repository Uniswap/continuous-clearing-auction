# ConstantsLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/69de3ae4ba8e1e42b571cd7d7900cef9574ede92/src/libraries/ConstantsLib.sol)

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


