# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/57168f679cba2e43cc601572a1c8354914505aab/src/libraries/BidLib.sol)


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

