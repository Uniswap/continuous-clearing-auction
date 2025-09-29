# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/3a2a79a8442dc1d66aca4be0c1d531db5a9f8424/src/interfaces/IAuction.sol)

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
    uint24 graduationThresholdMps;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    bytes auctionStepsData;
    bytes fundsRecipientData;
}
```

