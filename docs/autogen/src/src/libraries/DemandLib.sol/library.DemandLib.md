# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/07712f11fafad883cb4261b09b8cf07d1b82d868/src/libraries/DemandLib.sol)

Library for demand calculations and operations


## Functions
### resolveRoundingUp

Resolve the demand at a given price, rounding up

*"Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price*


```solidity
function resolveRoundingUp(Demand memory _demand, uint256 price) internal pure returns (ValueX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_demand`|`Demand`|The demand to resolve|
|`price`|`uint256`|The price to resolve the demand at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The resolved demand as a ValueX7|


### _resolveCurrencyDemandRoundingUp


```solidity
function _resolveCurrencyDemandRoundingUp(ValueX7 amount, uint256 price) private pure returns (ValueX7);
```

### add


```solidity
function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### sub


```solidity
function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### mulUint256


```solidity
function mulUint256(Demand memory _demand, uint256 value) internal pure returns (Demand memory);
```

