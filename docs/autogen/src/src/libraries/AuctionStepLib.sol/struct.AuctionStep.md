# AuctionStep
[Git Source](https://github.com/Uniswap/twap-auction/blob/468d53629b7c1620881cec3814c348b60ec958e9/src/libraries/AuctionStepLib.sol)


```solidity
struct AuctionStep {
uint24 mps; // Mps to sell per block in the step
uint64 startBlock; // Start block of the step (inclusive)
uint64 endBlock; // Ending block of the step (exclusive)
}
```

