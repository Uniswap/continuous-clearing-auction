# ValueX7Lib
[Git Source](https://github.com/Uniswap/twap-auction/blob/2ab6f1f651f977062136e0144a4f3e636a17d226/src/libraries/ValueX7Lib.sol)


## State Variables
### X7
The scaling factor for ValueX7 values (MPSLib.MPS)


```solidity
uint256 public constant X7 = MPSLib.MPS;
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


### wrapAndFullMulDiv

Wrapper around free fullMulDiv function to support cases where we want to use uint256 values

*Ensure that `b` and `c` should be compared against the ValueX7 value*


```solidity
function wrapAndFullMulDiv(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7);
```

### wrapAndFullMulDivUp

Wrapper around free fullMulDivUp function to support cases where we want to use uint256 values

*Ensure that `b` and `c` should be compared against the ValueX7 value*


```solidity
function wrapAndFullMulDivUp(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7);
```

