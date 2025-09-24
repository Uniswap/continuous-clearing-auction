# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/aa2ccd1c0e4c78c616e28068bb0b6a94f112645a/src/libraries/BidLib.sol)


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

