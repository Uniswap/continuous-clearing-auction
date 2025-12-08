# ValueX7Lib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/ValueX7Lib.sol)

**Title:**
ValueX7Lib


## State Variables
### X7
The scaling factor for ValueX7 values (ConstantsLib.MPS)


```solidity
uint256 public constant X7 = ConstantsLib.MPS
```


## Functions
### scaleUpToX7

Multiply a uint256 value by MPS

This ensures that future operations will not lose precision


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


