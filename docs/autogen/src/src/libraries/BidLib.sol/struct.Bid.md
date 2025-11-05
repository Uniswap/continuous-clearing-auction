# Bid
[Git Source](https://github.com/Uniswap/twap-auction/blob/468d53629b7c1620881cec3814c348b60ec958e9/src/libraries/BidLib.sol)


```solidity
struct Bid {
uint64 startBlock; // Block number when the bid was first made in
uint24 startCumulativeMps; // Cumulative mps at the start of the bid
uint64 exitedBlock; // Block number when the bid was exited
uint256 maxPrice; // The max price of the bid
address owner; // Who will receive the tokens filled and currency refunded
uint256 amountQ96; // User's currency amount in Q96 form
uint256 tokensFilled; // Amount of tokens filled
}
```

