# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/d1e7b82f3777bade51fea369dcee7819652c8bdc/src/libraries/BidLib.sol)


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

