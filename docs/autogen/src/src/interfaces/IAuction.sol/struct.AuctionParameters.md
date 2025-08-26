# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/ba0ef575d825ce397bf2f008f0cd27ea57bdbc58/src/interfaces/IAuction.sol)

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
}
```

