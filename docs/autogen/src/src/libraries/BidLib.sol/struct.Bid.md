# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/17cd795efcd7da4447d3746773588de7c190a183/src/libraries/BidLib.sol)


```solidity
struct Bid {
    uint64 startBlock;
    uint24 startCumulativeMps;
    uint64 exitedBlock;
    uint256 maxPrice;
    address owner;
    uint256 amount;
    uint256 tokensFilled;
}
```

