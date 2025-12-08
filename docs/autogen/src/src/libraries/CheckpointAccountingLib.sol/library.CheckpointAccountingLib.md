# CheckpointAccountingLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/CheckpointAccountingLib.sol)

**Title:**
CheckpointAccountingLib

Pure accounting helpers for computing fills and currency spent across checkpoints


## Functions
### accountFullyFilledCheckpoints

Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints

MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
because it uses lazy accounting to calculate the tokens filled


```solidity
function accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpentQ96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`upper`|`Checkpoint`|The upper checkpoint|
|`startCheckpoint`|`Checkpoint`|The start checkpoint of the bid|
|`bid`|`Bid`|The bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpentQ96`|`uint256`|The amount of currency spent in Q96 form|


### accountPartiallyFilledCheckpoints

Calculate the tokens sold and currency spent for a partially filled bid


```solidity
function accountPartiallyFilledCheckpoints(
    Bid memory bid,
    uint256 tickDemandQ96,
    ValueX7 currencyRaisedAtClearingPriceQ96_X7
) internal pure returns (uint256 tokensFilled, uint256 currencySpentQ96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The bid|
|`tickDemandQ96`|`uint256`|The total demand at the tick|
|`currencyRaisedAtClearingPriceQ96_X7`|`ValueX7`|The cumulative supply sold to the clearing price|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|The tokens sold|
|`currencySpentQ96`|`uint256`|The amount of currency spent in Q96 form|


### calculateFill

Calculate the tokens filled and currency spent for a bid

Uses lazy accounting to efficiently calculate fills across time periods without iterating blocks.
MUST only be used when the bid's max price is strictly greater than the clearing price throughout.


```solidity
function calculateFill(Bid memory bid, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
    internal
    pure
    returns (uint256 tokensFilled, uint256 currencySpentQ96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|the bid to evaluate|
|`cumulativeMpsPerPriceDelta`|`uint256`|the cumulative sum of supply to price ratio|
|`cumulativeMpsDelta`|`uint24`|the cumulative sum of mps values across the block range|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokensFilled`|`uint256`|the amount of tokens filled for this bid|
|`currencySpentQ96`|`uint256`|the amount of currency spent by this bid in Q96 form|


