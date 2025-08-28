# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/4c9af76a705eb813cc2e0ec768b3771f7a342ec1/src/libraries/BidLib.sol)


## State Variables
### PRECISION

```solidity
uint256 public constant PRECISION = 1e18;
```


## Functions
### demand

Resolve the demand of a bid at its maxPrice


```solidity
function demand(Bid memory bid) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The demand of the bid|


### inputAmount

Calculate the input amount required for an amount and maxPrice


```solidity
function inputAmount(bool exactIn, uint128 amount, uint256 maxPrice) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint128`|The amount of the bid|
|`maxPrice`|`uint256`|The max price of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The input amount required for an amount and maxPrice|


### inputAmount

Calculate the input amount required to place the bid


```solidity
function inputAmount(Bid memory bid) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The input amount required to place the bid|


