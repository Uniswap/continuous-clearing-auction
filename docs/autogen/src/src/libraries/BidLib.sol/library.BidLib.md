# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/c9923b6612650531d4151de2f459778059410469/src/libraries/BidLib.sol)

**Title:**
BidLib


## Functions
### mpsRemainingInAuctionAfterSubmission

Calculate the number of mps remaining in the auction since the bid was submitted


```solidity
function mpsRemainingInAuctionAfterSubmission(Bid memory bid) internal pure returns (uint24);
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
This is an important normalization step to ensure that we can calculate the currencyRaised
when cumulative demand is less than supply using the original supply schedule.


```solidity
function toEffectiveAmount(Bid memory bid) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid to scale|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The scaled amount|


## Errors
### MpsRemainingIsZero
Error thrown when a bid is submitted with no remaining percentage of the auction
This is prevented by the auction contract as bids cannot be submitted when the auction is sold out,
but we catch it instead of reverting with division by zero.


```solidity
error MpsRemainingIsZero();
```

