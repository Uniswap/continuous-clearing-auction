# ConstantsLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/93c0c780ed33d07191c07fe0752db1c29bbcb8f7/src/libraries/ConstantsLib.sol)

Library containing protocol constants


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 constant MPS = 1e7;
```


### X7_UPPER_BOUND
The upper bound of a ValueX7 value


```solidity
uint256 constant X7_UPPER_BOUND = (type(uint256).max) / 1e7;
```


### MAX_AMOUNT
The maximum allowable amount for currency or token related values


```solidity
uint128 constant MAX_AMOUNT = type(uint128).max / 1e7;
```


