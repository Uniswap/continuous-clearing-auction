# SupplyLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/63f4bfef19ba51e32937745adfe3603976e5bb51/src/libraries/SupplyLib.sol)

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


### REMAINING_CURRENCY_RAISED_MASK

```solidity
uint256 private constant REMAINING_CURRENCY_RAISED_MASK = (1 << 231) - 1;
```


### MAX_REMAINING_CURRENCY_RAISED_X7_X7
The maximum remaining currency raised as a ValueX7X7 which fits in 231 bits


```solidity
ValueX7X7 public constant MAX_REMAINING_CURRENCY_RAISED_X7_X7 = ValueX7X7.wrap(REMAINING_CURRENCY_RAISED_MASK);
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

*This function does NOT check that `remainingCurrencyRaisedX7X7` fits in 231 bits.
Given the total supply is capped at type(uint128).max, the largest `remainingCurrencyRaisedX7X7` value is
REMAINING_CURRENCY_RAISED_AT_FLOOR_X7_X7, which is 175 bits (type(uint128).max * 1e14)*


```solidity
function packSupplyRolloverMultiplier(bool set, uint24 remainingPercentage, ValueX7X7 remainingCurrencyRaisedX7X7)
    internal
    pure
    returns (SupplyRolloverMultiplier);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`set`|`bool`|Boolean flag indicating if the value is set which only happens after the auction becomes fully subscribed, at which point the supply schedule becomes deterministic based on the future supply schedule|
|`remainingPercentage`|`uint24`|The remaining percentage of the auction|
|`remainingCurrencyRaisedX7X7`|`ValueX7X7`|The remaining currency which will be raised|

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


