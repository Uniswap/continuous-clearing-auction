# AuctionStepLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/8ff641518f712786eeaa4d68467339757c589570/src/libraries/AuctionStepLib.sol)


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

