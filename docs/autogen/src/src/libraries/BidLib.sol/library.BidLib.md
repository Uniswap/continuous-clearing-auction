# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/17cd795efcd7da4447d3746773588de7c190a183/src/libraries/BidLib.sol)


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


