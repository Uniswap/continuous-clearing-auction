# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/371cb0f36b92bd941e1e8d26644b52a674dda04d/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

