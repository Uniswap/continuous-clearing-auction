# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/046dab769f5d2ea2e8b9bef5d784a4e50afa7ccd/src/libraries/BidLib.sol)


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

