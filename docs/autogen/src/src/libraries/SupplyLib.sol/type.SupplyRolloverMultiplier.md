# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/2ab6f1f651f977062136e0144a4f3e636a17d226/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

