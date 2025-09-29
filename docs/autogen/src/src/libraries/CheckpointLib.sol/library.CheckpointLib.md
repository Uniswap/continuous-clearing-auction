# CheckpointLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/ace0c8fa02a7f9ecc269c8d6adca532a0d0858dc/src/libraries/CheckpointLib.sol)


## Functions
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


