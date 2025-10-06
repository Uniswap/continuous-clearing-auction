# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/1a7f98b9e1cb9ed630b15a7f62d113994de8c338/src/libraries/CheckpointLib.sol)


## Functions
### remainingMpsInAuction

Get the remaining mps in the auction at the given checkpoint


```solidity
function remainingMpsInAuction(Checkpoint memory _checkpoint) internal pure returns (uint24);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint with `cumulativeMps` so far|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint24`|The remaining mps in the auction|


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

Return the total currency raised at the given checkpoint


```solidity
function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|the checkpoint|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total currency raised in uint256 form|


