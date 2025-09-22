# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/0870269de9eb67f838fdf37d31febd27dfdef28a/src/libraries/BidLib.sol)


```solidity
struct Bid {
    bool exactIn;
    uint64 startBlock;
    uint24 startCumulativeMps;
    uint64 exitedBlock;
    uint256 maxPrice;
    address owner;
    uint256 amount;
    uint256 tokensFilled;
}
```

