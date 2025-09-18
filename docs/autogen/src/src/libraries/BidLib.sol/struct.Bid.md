# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/4967de5a0312d620dba4bcfa654c49c4c495aad3/src/libraries/BidLib.sol)


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

