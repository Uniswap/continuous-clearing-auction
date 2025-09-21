# AuctionStepLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/libraries/AuctionStepLib.sol)


## State Variables
### MPS
we use milli-bips, or one thousandth of a basis point


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

