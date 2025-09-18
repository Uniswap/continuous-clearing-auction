# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/3f93841df89124f8b3dcf887da46cb2c78bfe137/src/libraries/BidLib.sol)


## State Variables
### PRECISION

```solidity
uint256 public constant PRECISION = 1e18;
```


## Functions
### effectiveAmount

Calculate the effective amount of a bid based on the mps denominator


```solidity
function effectiveAmount(uint256 amount, uint24 mpsDenominator) internal pure returns (ValueX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of the bid|
|`mpsDenominator`|`uint24`|The portion of the auction (in mps) which the bid was spread over|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ValueX7`|The effective amount of the bid|


### toDemand

Convert a bid to a demand


```solidity
function toDemand(Bid memory bid, uint24 mpsDenominator) internal pure returns (Demand memory demand);
```

### inputAmount

Calculate the input amount required for an amount and maxPrice


```solidity
function inputAmount(bool exactIn, uint256 amount, uint256 maxPrice) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|
|`maxPrice`|`uint256`|The max price of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The input amount required for an amount and maxPrice|


### inputAmount

Calculate the input amount required to place the bid


```solidity
function inputAmount(Bid memory bid) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The input amount required to place the bid|


