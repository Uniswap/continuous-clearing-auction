# AuctionParameters
[Git Source](https://github.com/Uniswap/twap-auction/blob/b4d0a06daced32c81e0487f3201e863948da89b2/src/interfaces/IContinuousClearingAuction.sol)

Parameters for the auction

token and totalSupply are passed as constructor arguments


```solidity
struct AuctionParameters {
address currency; // token to raise funds in. Use address(0) for ETH
address tokensRecipient; // address to receive leftover tokens
address fundsRecipient; // address to receive all raised funds
uint64 startBlock; // Block which the first step starts
uint64 endBlock; // When the auction finishes
uint64 claimBlock; // Block when the auction can claimed
uint256 tickSpacing; // Fixed granularity for prices
address validationHook; // Optional hook called before a bid
uint256 floorPrice; // Starting floor price for the auction
uint128 requiredCurrencyRaised; // Amount of currency required to be raised for the auction to graduate
bytes auctionStepsData; // Packed bytes describing token issuance schedule
}
```

