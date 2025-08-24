# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/03b283c54c5f2efd695e0da42cae5de574a91cf7/src/libraries/BidLib.sol)


## State Variables
### PRECISION

```solidity
uint256 public constant PRECISION = 1e18;
```


## Functions
### demand

Resolve the demand of a bid at its maxPrice


```solidity
function demand(Bid memory bid, bool currencyIsToken0) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|
|`currencyIsToken0`|`bool`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The demand of the bid|


### inputAmount

Calculate the input amount required for an amount and maxPrice


```solidity
function inputAmount(bool exactIn, uint256 amount, uint256 maxPrice, bool currencyIsToken0)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|
|`maxPrice`|`uint256`|The max price of the bid|
|`currencyIsToken0`|`bool`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The input amount required for an amount and maxPrice|


### inputAmount

Calculate the input amount required to place the bid


```solidity
function inputAmount(Bid memory bid, bool currencyIsToken0) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|
|`currencyIsToken0`|`bool`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The input amount required to place the bid|


