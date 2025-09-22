# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/7f8e9557cd2f0bf0814d12508e520cf2664be393/src/libraries/BidLib.sol)


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

