# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/cfe064d2fdebcf6b4861fcd47553d75e33aa20ae/src/libraries/BidLib.sol)


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

