# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/0a5b39a6c7a8e647dc0617b7ec4d2db5ff917aa5/src/libraries/BidLib.sol)


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

