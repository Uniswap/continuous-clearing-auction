# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/9108275bb2b2739632f86ff78401b370ae2d4f3d/src/libraries/BidLib.sol)


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

