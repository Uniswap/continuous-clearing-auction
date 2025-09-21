# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/libraries/BidLib.sol)


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

