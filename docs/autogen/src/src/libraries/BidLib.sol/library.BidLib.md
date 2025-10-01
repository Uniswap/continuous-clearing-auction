# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/7481976d9a045c9df236ecc1331ce832ed4d18a0/src/libraries/BidLib.sol)


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


### toEffectiveAmount

Scale a bid amount to its effective amount over the remaining percentage of the auction

*The amount is scaled based on the remaining mps such that it is fully allocated over the remaining parts of the auction*


```solidity
function toEffectiveAmount(Bid memory bid) internal pure returns (ValueX7 bidAmountOverRemainingAuctionX7);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid to convert|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidAmountOverRemainingAuctionX7`|`ValueX7`|The bid amount in ValueX7 scaled to the remaining percentage of the auction|


### inputAmount

Calculate the input amount required for an amount and maxPrice


```solidity
function inputAmount(uint256 amount, uint256 maxPrice) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
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


