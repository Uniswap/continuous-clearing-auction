# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/45bab3c8875b0df2a6d4a56c26add6ec4f6a45f5/src/libraries/BidLib.sol)


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

