# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/libraries/BidLib.sol)


## State Variables
### PRECISION

```solidity
uint256 public constant PRECISION = 1e18;
```


## Functions
### validate

Validate a bid

*The bid must be greater than the clearing price and at a tick boundary*


```solidity
function validate(uint256 maxPrice, uint256 clearingPrice, uint256 tickSpacing) internal pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The max price of the bid|
|`clearingPrice`|`uint256`|The clearing price of the auction|
|`tickSpacing`|`uint256`|The tick spacing of the auction|


### demand

Resolve the demand of a bid at its maxPrice


```solidity
function demand(Bid memory bid) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The demand of the bid|


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


## Errors
### InvalidBidPrice

```solidity
error InvalidBidPrice();
```

