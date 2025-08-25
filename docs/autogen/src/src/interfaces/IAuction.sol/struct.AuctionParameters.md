# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/8f0cdceab8341bbaf5daef9ba1cd7a3cb87561d1/src/interfaces/IAuction.sol)

Parameters for the auction

*token and totalSupply are passed as constructor arguments*


```solidity
struct AuctionParameters {
    address currency;
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint64 endBlock;
    uint64 claimBlock;
    uint64 fundsRecipientDeadlineBlock;
    uint24 graduationThresholdMps;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    bytes auctionStepsData;
}
```

