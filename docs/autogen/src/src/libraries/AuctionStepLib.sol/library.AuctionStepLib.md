# AuctionStepLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/417428be9c09d153c63b5c6214c7a36520bc515b/src/libraries/AuctionStepLib.sol)

Library for auction step calculations and parsing


## State Variables
### MPS
Maximum value for milli-bips (mps), representing 100% in ten-millionths


```solidity
uint24 public constant MPS = 1e7;
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

### applyMps

Apply mps to a value

*Requires that value is > MPS to avoid loss of precision*


```solidity
function applyMps(uint128 value, uint24 mps) internal pure returns (uint128);
```

