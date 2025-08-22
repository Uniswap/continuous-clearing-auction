# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/interfaces/IAuction.sol)

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

