# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/libraries/BidLib.sol)


## State Variables
### PRECISION

```solidity
uint256 public constant PRECISION = 1e18;
```


## Functions
### effectiveAmount

Calculate the effective amount of a bid based on the mps denominator


```solidity
function effectiveAmount(uint128 amount, uint24 mpsDenominator) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint128`|The amount of the bid|
|`mpsDenominator`|`uint24`|The percentage of the auction which the bid was spread over|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The effective amount of the bid|


### demand

Resolve the demand of a bid at its maxPrice


```solidity
function demand(Bid memory bid, uint24 mpsDenominator) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|
|`mpsDenominator`|`uint24`|The percentage of the auction which the bid was spread over|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The demand of the bid|


### inputAmount

Calculate the input amount required for an amount and maxPrice


```solidity
function inputAmount(bool exactIn, uint128 amount, uint256 maxPrice) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint128`|The amount of the bid|
|`maxPrice`|`uint256`|The max price of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The input amount required for an amount and maxPrice|


### inputAmount

Calculate the input amount required to place the bid


```solidity
function inputAmount(Bid memory bid) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The input amount required to place the bid|


