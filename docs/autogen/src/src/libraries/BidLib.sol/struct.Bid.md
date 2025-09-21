# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/4a2534467c505f9bb8c4a942d2cc4f01d7d061ef/src/libraries/BidLib.sol)


```solidity
struct Bid {
    bool exactIn;
    uint64 startBlock;
    uint64 exitedBlock;
    uint256 maxPrice;
    address owner;
    uint128 amount;
    uint128 tokensFilled;
}
```

