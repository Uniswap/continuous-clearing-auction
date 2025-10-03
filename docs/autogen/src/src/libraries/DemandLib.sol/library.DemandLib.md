# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/DemandLib.sol)

Library for helper functions related to demand resolution


## Functions
### resolveRoundingUp

Resolve the demand at a given price, rounding up.
We only round up when we compare demand to supply so we never find a price that is too low.

*"Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price*


```solidity
function resolveRoundingUp(ValueX7 currencyDemandX7, uint256 price) internal pure returns (ValueX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyDemandX7`|`ValueX7`|The demand to resolve|
|`price`|`uint256`|The price to resolve the demand at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The resolved demand as a ValueX7|


### resolveRoundingDown

Resolve the demand at a given price, rounding down
We always round demand down in all other cases (calculating supply sold to a price and bid withdrawals)

*"Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price*


```solidity
function resolveRoundingDown(ValueX7 currencyDemandX7, uint256 price) internal pure returns (ValueX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currencyDemandX7`|`ValueX7`|The demand to resolve|
|`price`|`uint256`|The price to resolve the demand at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The resolved demand as a ValueX7|


