# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/CheckpointLib.sol)


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

Calculate the total currency raised


```solidity
function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`checkpoint`|`Checkpoint`|The checkpoint to calculate the currency raised from|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total currency raised|


