# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/6199a07349a5d22f79f49db95ea478090bd8c68d/src/libraries/BidLib.sol)


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

