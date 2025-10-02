# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/57168f679cba2e43cc601572a1c8354914505aab/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingSupplyX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

