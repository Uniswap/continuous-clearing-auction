# saturatingSub
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/libraries/ValueX7Lib.sol)

Subtract two ValueX7 values, returning zero on underflow.

Wrapper around FixedPointMathLib.saturatingSub


```solidity
function saturatingSub(ValueX7 a, ValueX7 b) pure returns (ValueX7);
```

