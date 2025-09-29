# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/ace0c8fa02a7f9ecc269c8d6adca532a0d0858dc/src/libraries/BidLib.sol)


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

