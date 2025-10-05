# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/8c2930146e31b54e368caa772ec5bb20d1a47d12/src/interfaces/IAuction.sol)

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

