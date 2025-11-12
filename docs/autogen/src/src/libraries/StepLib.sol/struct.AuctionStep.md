# AuctionStep
[Git Source](https://github.com/Uniswap/twap-auction/blob/b4d0a06daced32c81e0487f3201e863948da89b2/src/libraries/StepLib.sol)


```solidity
struct AuctionStep {
uint24 mps; // Mps to sell per block in the step
uint64 startBlock; // Start block of the step (inclusive)
uint64 endBlock; // Ending block of the step (exclusive)
}
```

