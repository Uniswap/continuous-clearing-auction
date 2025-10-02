# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/f4ca3ef3995c04dfc87924fa2a7301b4b6eb60a2/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

