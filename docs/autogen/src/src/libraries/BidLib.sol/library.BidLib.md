# BidLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/63f4bfef19ba51e32937745adfe3603976e5bb51/src/libraries/BidLib.sol)


## State Variables
### MIN_BID_AMOUNT
The minimum allowable amount for a bid such that is not rounded down to zero


```solidity
uint256 public constant MIN_BID_AMOUNT = ValueX7Lib.X7;
```


### MAX_BID_AMOUNT
The maximum allowable amount for a bid such that it will not overflow a ValueX7X7 value


```solidity
uint256 public constant MAX_BID_AMOUNT = ConstantsLib.X7X7_UPPER_BOUND - 1;
```


### MAX_BID_PRICE
The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.


```solidity
uint256 public constant MAX_BID_PRICE =
    26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917;
```


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

*The amount is scaled based on the remaining mps such that it is fully allocated over the remaining parts of the auction
It is not possible to avoid the division here because we must include the scaled up demand
into tick demand and `sumCurrencyDemandAboveClearingX7` where we have no way to preserve the bid-level information.*


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


