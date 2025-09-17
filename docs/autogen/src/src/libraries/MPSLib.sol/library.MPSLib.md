# MPSLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/ce0cdcca7cbcb44361047d64c159d39b69b75e36/src/libraries/MPSLib.sol)


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


```solidity
uint24 public constant MPS = 1e7;
```


## Functions
### scaleUp


```solidity
function scaleUp(uint256 value) internal pure returns (ValueX7);
```

### scaleDown


```solidity
function scaleDown(ValueX7 value) internal pure returns (uint256);
```

### applyMps

Apply mps to a value

*Requires that value is > MPS to avoid loss of precision*


```solidity
function applyMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7);
```

