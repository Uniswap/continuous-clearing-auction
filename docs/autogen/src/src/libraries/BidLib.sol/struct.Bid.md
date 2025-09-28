# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/0ee04bc2c45f6d51f37030260f300f404e183bf7/src/libraries/BidLib.sol)


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

