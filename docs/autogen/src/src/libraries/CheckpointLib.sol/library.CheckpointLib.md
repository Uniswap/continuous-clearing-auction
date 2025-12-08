# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/CheckpointLib.sol)

**Title:**
CheckpointLib


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

This function returns a value in Q96 form


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


