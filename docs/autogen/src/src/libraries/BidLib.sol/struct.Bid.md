# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/178972dc4928b279780e4b89ace792a3f28b8ea5/src/libraries/BidLib.sol)


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

