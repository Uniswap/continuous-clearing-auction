# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/BidLib.sol)


## State Variables
### MAX_BID_PRICE
The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.


```solidity
uint256 public constant MAX_BID_PRICE =
    26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917;
```


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


