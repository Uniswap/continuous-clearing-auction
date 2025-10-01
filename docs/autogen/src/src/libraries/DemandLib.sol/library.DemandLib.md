# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/f53d7155325c22ef28d878c4d9443735141b48d7/src/libraries/DemandLib.sol)

Library for demand calculations and operations


## Functions
### resolveRoundingUp

Resolve the demand at a given price, rounding up.
We only round up when we compare demand to supply so we never find a price that is too low.

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


### resolveRoundingDown

Resolve the demand at a given price, rounding down
We always round demand down in all other cases (calculating supply sold to a price and bid withdrawals)

*"Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price*


```solidity
function resolveRoundingDown(Demand memory _demand, uint256 price) internal pure returns (ValueX7);
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

### _resolveCurrencyDemandRoundingDown


```solidity
function _resolveCurrencyDemandRoundingDown(ValueX7 amount, uint256 price) private pure returns (ValueX7);
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

