# AuctionStepLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/d2fa994e75f232a6bfe496080d6fadb2906a187d/src/libraries/AuctionStepLib.sol)

Library for auction step calculations and parsing


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

