# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/3c95f1e080149f3b4149fa29f3305216cb44fbf5/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingCurrencyRaisedX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

