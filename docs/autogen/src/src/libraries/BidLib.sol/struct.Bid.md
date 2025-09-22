# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/9947ebc29ae68f1eff00f7c7cabe2dd5389ebcb1/src/libraries/BidLib.sol)


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

