# ValueX7X7Lib
[Git Source](https://github.com/Uniswap/twap-auction/blob/43737e6643fccd8bba6b520bad93b4c795de35b0/src/libraries/ValueX7X7Lib.sol)


## Functions
### scaleUpToX7X7

Multiply a uint256 value by MPS

*This ensures that future operations (ex. scaleByMps) will not lose precision*


```solidity
function scaleUpToX7X7(ValueX7 value) internal pure returns (ValueX7X7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7X7`|The result as a ValueX7X7|


### upcast

Upcast a ValueX7 value to a ValueX7X7 value


```solidity
function upcast(ValueX7 value) internal pure returns (ValueX7X7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7X7`|the value as a ValueX7X7|


### downcast

Downcast a ValueX7X7 value to a ValueX7 value


```solidity
function downcast(ValueX7X7 value) internal pure returns (ValueX7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|the value as a ValueX7|


### scaleDownToValueX7

Divide a ValueX7X7 value by MPS


```solidity
function scaleDownToValueX7(ValueX7X7 value) internal pure returns (ValueX7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The result as a ValueX7|


### wrapAndFullMulDiv

Wrapper around free fullMulDiv function to support cases where we want to use uint256 values

*Ensure that `b` and `c` should be compared against the ValueX7X7 value*


```solidity
function wrapAndFullMulDiv(ValueX7X7 a, uint256 b, uint256 c) internal pure returns (ValueX7X7);
```

### wrapAndFullMulDivUp

Wrapper around free fullMulDivUp function to support cases where we want to use uint256 values

*Ensure that `b` and `c` should be compared against the ValueX7X7 value*


```solidity
function wrapAndFullMulDivUp(ValueX7X7 a, uint256 b, uint256 c) internal pure returns (ValueX7X7);
```

