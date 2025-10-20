# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/93c0c780ed33d07191c07fe0752db1c29bbcb8f7/src/libraries/BidLib.sol)


```solidity
struct Bid {
    uint64 startBlock;
    uint24 startCumulativeMps;
    uint64 exitedBlock;
    uint256 maxPrice;
    address owner;
    uint256 amountQ96;
    uint256 tokensFilled;
}
```

