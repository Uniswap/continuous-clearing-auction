# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/89f9182c5a4250ce7345e6305d6fe12fceb138f4/src/libraries/BidLib.sol)


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

