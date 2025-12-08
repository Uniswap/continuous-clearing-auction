# AuctionState
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/lens/AuctionStateLens.sol)

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

