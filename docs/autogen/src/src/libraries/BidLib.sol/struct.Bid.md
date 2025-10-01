# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/7481976d9a045c9df236ecc1331ce832ed4d18a0/src/libraries/BidLib.sol)


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

