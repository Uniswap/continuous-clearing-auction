# AuctionState
[Git Source](https://github.com/Uniswap/twap-auction/blob/64f5212a4573a22c85e9c110002cc1ad74f5e008/src/lens/AuctionStateLens.sol)

The state of the auction containing the latest checkpoint
as well as the currency raised, total cleared, and whether the auction has graduated


```solidity
struct AuctionState {
Checkpoint checkpoint;
uint256 currencyRaised;
uint256 totalCleared;
bool isGraduated;
}
```

