# ValueX7Lib
[Git Source](https://github.com/Uniswap/twap-auction/blob/468d53629b7c1620881cec3814c348b60ec958e9/src/libraries/ValueX7Lib.sol)


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


### wrapAndFullMulDiv

Helper wrapper around fullMulDiv to support operations with uint256 values


```solidity
function wrapAndFullMulDiv(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7);
```

### wrapAndFullMulDivUp

Helper wrapper around fullMulDivUp to support operations with uint256 values


```solidity
function wrapAndFullMulDivUp(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7);
```

