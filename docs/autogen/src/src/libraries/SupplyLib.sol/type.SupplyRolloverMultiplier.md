# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/68d18000c60b2a641f136e527165de89b151504d/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

