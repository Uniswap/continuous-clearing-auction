# AuctionState
[Git Source](https://github.com/Uniswap/twap-auction/blob/c9923b6612650531d4151de2f459778059410469/src/lens/AuctionStateLens.sol)

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

