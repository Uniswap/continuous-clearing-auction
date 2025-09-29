# SupplyLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/2ab6f1f651f977062136e0144a4f3e636a17d226/src/libraries/SupplyLib.sol)

Library for supply related functions


## State Variables
### REMAINING_MPS_BIT_POSITION

```solidity
uint256 private constant REMAINING_MPS_BIT_POSITION = 231;
```


### REMAINING_MPS_SIZE

```solidity
uint256 private constant REMAINING_MPS_SIZE = 24;
```


### SET_FLAG_MASK

```solidity
uint256 private constant SET_FLAG_MASK = 1 << 255;
```


### REMAINING_MPS_MASK

```solidity
uint256 private constant REMAINING_MPS_MASK = ((1 << REMAINING_MPS_SIZE) - 1) << REMAINING_MPS_BIT_POSITION;
```


### REMAINING_SUPPLY_MASK

```solidity
uint256 private constant REMAINING_SUPPLY_MASK = (1 << 231) - 1;
```


### MAX_REMAINING_SUPPLY

```solidity
uint256 public constant MAX_REMAINING_SUPPLY = REMAINING_SUPPLY_MASK;
```


### MAX_TOTAL_SUPPLY
The maximum total supply of tokens than can be sold in the auction


```solidity
uint256 public constant MAX_TOTAL_SUPPLY = MAX_REMAINING_SUPPLY / ValueX7Lib.X7 ** 2;
```


## Functions
### toX7X7

Convert the total supply to a ValueX7X7

*This function must be checked for overflow before being called*


```solidity
function toX7X7(uint256 totalSupply) internal pure returns (ValueX7X7);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7X7`|The total supply as a ValueX7X7|


### packSupplyRolloverMultiplier

Pack values into a SupplyRolloverMultiplier

*This function does NOT check that `remainingSupplyX7X7` fits in 231 bits.
TOTAL_SUPPLY_X7_X7, which bounds the value of `remainingSupplyX7X7`, must be validated.*


```solidity
function packSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
    internal
    pure
    returns (SupplyRolloverMultiplier);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`set`|`bool`|Boolean flag indicating if the value is set which only happens after the auction becomes fully subscribed, at which point the supply schedule becomes deterministic based on the future supply schedule|
|`remainingMps`|`uint24`|The remaining MPS value|
|`remainingSupplyX7X7`|`ValueX7X7`|The remaining supply value|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`SupplyRolloverMultiplier`|The packed SupplyRolloverMultiplier|


### unpack

Unpack a SupplyRolloverMultiplier into its components


```solidity
function unpack(SupplyRolloverMultiplier multiplier) internal pure returns (bool, uint24, ValueX7X7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`multiplier`|`SupplyRolloverMultiplier`|The packed SupplyRolloverMultiplier|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|The unpacked components|
|`<none>`|`uint24`||
|`<none>`|`ValueX7X7`||


