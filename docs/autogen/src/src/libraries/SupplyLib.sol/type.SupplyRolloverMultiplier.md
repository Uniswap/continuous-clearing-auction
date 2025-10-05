# SupplyRolloverMultiplier
[Git Source](https://github.com/Uniswap/twap-auction/blob/35473874d97222cd9ba85c79c74cfb5935603cd9/src/libraries/SupplyLib.sol)

*Custom type layout (256 bits total):
- Bit 255 (MSB): Boolean 'set' flag
- Bits 254-231 (24 bits): 'remainingMps' value
- Bits 230-0 (231 bits): 'remainingCurrencyRaisedX7X7' value*


```solidity
type SupplyRolloverMultiplier is uint256;
```

