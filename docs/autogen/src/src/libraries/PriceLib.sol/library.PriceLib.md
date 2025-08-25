# PriceLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/d124733ccbf34ad38274ee9b55ab6da88f47decd/src/libraries/PriceLib.sol)


## Functions
### priceStrictlyBefore

Returns true if price1 is strictly ordered before price2

*Prices will be monotonically increasing if currency is token1 and monotonically decreasing if currency is token0*


```solidity
function priceStrictlyBefore(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool);
```

### priceBeforeOrEqual

Returns true if price1 is ordered before or equal to price2

*Prices will be monotonically increasing if currency is token1 and monotonically decreasing if currency is token0*


```solidity
function priceBeforeOrEqual(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool);
```

### priceStrictlyAfter

Returns true if price1 is strictly ordered after price2

*Prices will be monotonically increasing if currency is token1 and monotonically decreasing if currency is token0*


```solidity
function priceStrictlyAfter(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool);
```

### priceAfterOrEqual

Returns true if price1 is ordered after or equal to price2

*Prices will be monotonically increasing if currency is token1 and monotonically decreasing if currency is token0*


```solidity
function priceAfterOrEqual(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool);
```

