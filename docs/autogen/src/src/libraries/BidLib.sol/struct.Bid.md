# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/f53d7155325c22ef28d878c4d9443735141b48d7/src/libraries/BidLib.sol)


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

