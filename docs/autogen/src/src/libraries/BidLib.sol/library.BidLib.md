# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/07712f11fafad883cb4261b09b8cf07d1b82d868/src/libraries/BidLib.sol)


## Functions
### mpsRemainingInAuction

Calculate the number of mps remaining in the auction since the bid was submitted


```solidity
function mpsRemainingInAuction(Bid memory bid) internal pure returns (uint24);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid to calculate the remaining mps for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint24`|The number of mps remaining in the auction|


### toDemand

Convert a bid to a demand

*The demand is scaled based on the remaining mps such that it is fully allocated over the remaining parts of the auction*


```solidity
function toDemand(Bid memory bid) internal pure returns (Demand memory demand);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid to convert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`demand`|`Demand`|The demand struct representing the bid|


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


