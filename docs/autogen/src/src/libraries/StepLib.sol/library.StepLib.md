# StepLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/b4d0a06daced32c81e0487f3201e863948da89b2/src/libraries/StepLib.sol)

Library for auction step calculations and parsing


## State Variables
### UINT64_SIZE
The size of a uint64 in bytes


```solidity
uint256 public constant UINT64_SIZE = 8
```


## Functions
### parse

Unpack the mps and block delta from the auction steps data


```solidity
function parse(bytes8 data) internal pure returns (uint24 mps, uint40 blockDelta);
```

### get

Load a word at `offset` from data and parse it into mps and blockDelta


```solidity
function get(bytes memory data, uint256 offset) internal pure returns (uint24 mps, uint40 blockDelta);
```

## Errors
### StepLib__InvalidOffsetTooLarge
Error thrown when the offset is too large for the data length


```solidity
error StepLib__InvalidOffsetTooLarge();
```

### StepLib__InvalidOffsetNotAtStepBoundary
Error thrown when the offset is not at a step boundary - a uint64 aligned offset


```solidity
error StepLib__InvalidOffsetNotAtStepBoundary();
```

