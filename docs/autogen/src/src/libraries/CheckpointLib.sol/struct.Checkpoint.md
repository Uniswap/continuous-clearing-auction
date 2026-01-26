# Checkpoint
[Git Source](https://github.com/Uniswap/twap-auction/blob/468d53629b7c1620881cec3814c348b60ec958e9/src/libraries/CheckpointLib.sol)


```solidity
struct Checkpoint {
uint256 clearingPrice; // The X96 price which the auction is currently clearing at
ValueX7 currencyRaisedAtClearingPriceQ96_X7; // The currency raised so far to this clearing price
uint256 cumulativeMpsPerPrice; // A running sum of the ratio between mps and price
uint24 cumulativeMps; // The number of mps sold in the auction so far (via the original supply schedule)
uint64 prev; // Block number of the previous checkpoint
uint64 next; // Block number of the next checkpoint
}
```

