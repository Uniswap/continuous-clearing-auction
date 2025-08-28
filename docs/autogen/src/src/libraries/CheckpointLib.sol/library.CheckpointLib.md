# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/ca9baa0f4ab5e1713f915e16ec913f5984be79da/src/libraries/CheckpointLib.sol)


## Functions
### transform

Return a new checkpoint after advancing the current checkpoint by a number of blocks

*The checkpoint must have a non zero clearing price*


```solidity
function transform(
    Checkpoint memory checkpoint,
    uint256 totalSupply,
    uint256 floorPrice,
    uint256 blockDelta,
    uint24 mps
) internal pure returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The checkpoint to transform|
|`totalSupply`|`uint256`|The total supply of the auction|
|`floorPrice`|`uint256`|The floor price of the auction|
|`blockDelta`|`uint256`|The number of blocks to advance|
|`mps`|`uint24`|The number of mps to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The transformed checkpoint|


### getSupplySoldToClearingPrice

Calculate the supply sold to the clearing price


```solidity
function getSupplySoldToClearingPrice(uint256 supplyMps, uint256 resolvedDemandAboveClearingPrice, uint24 mpsDelta)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`supplyMps`|`uint256`|The supply of the auction|
|`resolvedDemandAboveClearingPrice`|`uint256`|The demand above the clearing price|
|`mpsDelta`|`uint24`|The number of mps to add|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|an X96 fixed point number representing the partial fill rate|


### getSupply

Calculate the actualy supply to sell given the total cleared in the auction so far


```solidity
function getSupply(Checkpoint memory checkpoint, uint256 totalSupply, uint24 mps) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The last checkpointed state of the auction|
|`totalSupply`|`uint256`|immutable total supply of the auction|
|`mps`|`uint24`|the number of mps, following the auction sale schedule|


### getBlockCleared

Get the amount of tokens sold in a block at a checkpoint based on its clearing price and the floorPrice


```solidity
function getBlockCleared(Checkpoint memory checkpoint, uint256 supply, uint256 floorPrice)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The last checkpointed state of the auction|
|`supply`|`uint256`|The supply being sold|
|`floorPrice`|`uint256`|immutable floor price of the auction|


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


