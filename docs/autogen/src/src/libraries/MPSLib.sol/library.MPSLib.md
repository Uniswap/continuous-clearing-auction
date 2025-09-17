# MPSLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/94b6014be30336d3af58264dcb1a5e840671c7b6/src/libraries/MPSLib.sol)

Library for working with MPS related values


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 public constant MPS = 1e7;
```


## Functions
### scaleUp

Multiply a uint256 value by MPS

*This ensures that future operations (ex. applyMps) will not lose precision*


```solidity
function scaleUp(uint256 value) internal pure returns (ValueX7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The result as a ValueX7|


### scaleDown

Divide a ValueX7 value by MPS


```solidity
function scaleDown(ValueX7 value) internal pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The result as a uint256|


### applyMps

Apply some `mps` to a ValueX7

*Only operates on ValueX7 values to not lose precision from dividing by MPS*


```solidity
function applyMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`value`|`ValueX7`|The ValueX7 value to apply `mps` to|
|`mps`|`uint24`|The number of mps to apply|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The result as a ValueX7|


