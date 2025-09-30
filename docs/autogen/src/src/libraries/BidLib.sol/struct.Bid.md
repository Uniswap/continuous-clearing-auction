# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/4e79543472823ca4f19066f04f5392aba6563627/src/libraries/BidLib.sol)


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

