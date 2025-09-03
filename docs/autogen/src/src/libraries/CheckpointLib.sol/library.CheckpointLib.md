# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/e6ae006b4d791723cfa088f0c2d93768cc82ee16/src/libraries/CheckpointLib.sol)


## Functions
### getSupplySoldToClearingPrice

Calculate the supply sold to the clearing price


```solidity
function getSupplySoldToClearingPrice(uint128 supplyMps, uint128 resolvedDemandAboveClearingPriceMps)
    internal
    pure
    returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`supplyMps`|`uint128`|The supply of the auction over `mps`|
|`resolvedDemandAboveClearingPriceMps`|`uint128`|The demand above the clearing price over `mps`|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|an X96 fixed point number representing the partial fill rate|


### getSupply

Calculate the actual supply to sell given the total cleared in the auction so far


```solidity
function getSupply(Checkpoint memory checkpoint, uint128 totalSupply, uint24 mps) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The last checkpointed state of the auction|
|`totalSupply`|`uint128`|immutable total supply of the auction|
|`mps`|`uint24`|the number of mps, following the auction sale schedule|


### getBlockCleared

Get the amount of tokens sold in a block at a checkpoint based on its clearing price and the floorPrice


```solidity
function getBlockCleared(Checkpoint memory checkpoint, uint128 supply, uint256 floorPrice)
    internal
    pure
    returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The last checkpointed state of the auction|
|`supply`|`uint128`|The supply being sold|
|`floorPrice`|`uint256`|immutable floor price of the auction|


### getMpsPerPrice

Calculate the supply to price ratio. Will return zero if `price` is zero

*This function returns a value in Q96 form*


```solidity
function getMpsPerPrice(uint24 mps, uint256 price) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`mps`|`uint24`|The number of supply mps sold|
|`price`|`uint256`|The price they were sold at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|the ratio|


### getCurrencyRaised

Calculate the total currency raised


```solidity
function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint128);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The checkpoint to calculate the currency raised from|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint128`|The total currency raised|


