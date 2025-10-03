# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

