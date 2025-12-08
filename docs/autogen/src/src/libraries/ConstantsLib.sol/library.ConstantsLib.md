# ConstantsLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/ConstantsLib.sol)

**Title:**
ConstantsLib

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


### MAX_TOTAL_SUPPLY
The maximum total supply of tokens that can be sold in the Auction

This is set to 2^100 tokens, which is just above 1e30, or one trillion units of a token with 18 decimals.
This upper bound is chosen to prevent the Auction from being used with an extremely large token supply,
which would restrict the clearing price to be a very low price in the calculation below.


```solidity
uint128 constant MAX_TOTAL_SUPPLY = 1 << 100
```


### MIN_FLOOR_PRICE
The minimum allowable floor price is type(uint32).max + 1

This is the minimum price that fits in a uint160 after being inversed


```solidity
uint256 constant MIN_FLOOR_PRICE = uint256(type(uint32).max) + 1
```


### MIN_TICK_SPACING
The minimum allowable tick spacing

We don't support tick spacings of 1 to avoid edge cases where the rounding of the clearing price
would cause the price to move between initialized ticks.


```solidity
uint256 constant MIN_TICK_SPACING = 2
```


