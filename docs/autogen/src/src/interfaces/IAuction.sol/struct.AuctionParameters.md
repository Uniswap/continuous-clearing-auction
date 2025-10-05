# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/3c95f1e080149f3b4149fa29f3305216cb44fbf5/src/interfaces/IAuction.sol)

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
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    bytes auctionStepsData;
}
```

