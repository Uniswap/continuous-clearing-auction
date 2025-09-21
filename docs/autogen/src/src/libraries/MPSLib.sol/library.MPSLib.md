# MPSLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/60abcc13bc954ef69471e1981dc9965a554c3331/src/libraries/MPSLib.sol)

Library for working with MPS related values


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 public constant MPS = 1e7;
```


## Functions
### scaleUpToX7

Multiply a uint256 value by MPS

*This ensures that future operations (ex. scaleByMps) will not lose precision*


```solidity
function scaleUpToX7(uint256 value) internal pure returns (ValueX7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The result as a ValueX7|


### scaleDownToUint256

Divide a ValueX7 value by MPS


```solidity
function scaleDownToUint256(ValueX7 value) internal pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The result as a uint256|


### scaleByMps

Apply some `mps` to a ValueX7

*Only operates on ValueX7 values to not lose precision from dividing by MPS*


```solidity
function scaleByMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7);
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


