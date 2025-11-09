# ConstantsLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/b619ad417255dd52e751fc565c8955914dbf07f4/src/libraries/ConstantsLib.sol)

Library containing protocol constants


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 constant MPS = 1e7
```


### X7_UPPER_BOUND
The upper bound of a ValueX7 value


```solidity
uint256 constant X7_UPPER_BOUND = type(uint256).max / 1e7
```


### MIN_TICK_SPACING
The minimum allowable tick spacing

We don't allow tick spacing of 1 to avoid edge cases where the rounding of the clearing price
would cause the price to move between initialized ticks.


```solidity
uint256 constant MIN_TICK_SPACING = 2
```


### MAX_BID_PRICE
The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.


```solidity
uint256 constant MAX_BID_PRICE =
    26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917
```


