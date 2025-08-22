# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/95d02e3e7495a7b877fb15da76e79ca2d28e1d25/src/interfaces/IAuction.sol)

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
    uint64 notifyBlock;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    bytes auctionStepsData;
    ISubscriber[] subscribers;
}
```

