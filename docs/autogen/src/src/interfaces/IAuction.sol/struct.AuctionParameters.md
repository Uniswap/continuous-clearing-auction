# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/4a2534467c505f9bb8c4a942d2cc4f01d7d061ef/src/interfaces/IAuction.sol)

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

