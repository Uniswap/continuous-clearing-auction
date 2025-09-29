# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/d2fa994e75f232a6bfe496080d6fadb2906a187d/src/libraries/BidLib.sol)


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

