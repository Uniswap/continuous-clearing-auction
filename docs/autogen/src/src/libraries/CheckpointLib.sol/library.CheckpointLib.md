# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/925b9803fc5f67f28a80cfa7e37eaf409feb8843/src/libraries/CheckpointLib.sol)


## Functions
### transform

Return a new checkpoint after advancing the current checkpoint by a number of blocks

*The checkpoint must have a non zero clearing price*


```solidity
function transform(Checkpoint memory checkpoint, uint256 blockDelta, uint24 mps)
    internal
    pure
    returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The checkpoint to transform|
|`blockDelta`|`uint256`|The number of blocks to advance|
|`mps`|`uint24`|The number of mps to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The transformed checkpoint|


### getMpsPerPrice

Calculate the supply to price ratio

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


