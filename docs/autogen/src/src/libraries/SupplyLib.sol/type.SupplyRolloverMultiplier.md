# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/1a7f98b9e1cb9ed630b15a7f62d113994de8c338/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingCurrencyRaisedX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

