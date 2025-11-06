# StepStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/b4d0a06daced32c81e0487f3201e863948da89b2/src/StepStorage.sol)

**Inherits:**
[IStepStorage](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/IStepStorage.sol/interface.IStepStorage.md)

Abstract contract to store and read information about the auction issuance schedule


## State Variables
### START_BLOCK
The block at which the auction starts


```solidity
uint64 internal immutable START_BLOCK
```


### END_BLOCK
The block at which the auction ends


```solidity
uint64 internal immutable END_BLOCK
```


### _LENGTH
Cached length of the auction steps data provided in the constructor


```solidity
uint256 internal immutable _LENGTH
```


### $_pointer
The address pointer to the contract deployed by SSTORE2


```solidity
address private immutable $_pointer
```


### $_offset
The word offset of the last read step in `auctionStepsData` bytes


```solidity
uint256 private $_offset
```


### $step
The current active auction step


```solidity
AuctionStep internal $step
```


## Functions
### constructor


```solidity
constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock) ;
```

### _validate

Validate the data provided in the constructor

Checks that the contract was correctly deployed by SSTORE2 and that the total mps and blocks are valid


```solidity
function _validate(address _pointer) internal view;
```

### _advanceStep

Advance the current auction step

This function is called on every new bid if the current step is complete


```solidity
function _advanceStep() internal returns (AuctionStep memory);
```

### step

Get the current active auction step


```solidity
function step() external view returns (AuctionStep memory);
```

### startBlock

The block at which the auction starts


```solidity
function startBlock() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The starting block number|


### endBlock

The block at which the auction ends


```solidity
function endBlock() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The ending block number|


### pointer

The address pointer to the contract deployed by SSTORE2


```solidity
function pointer() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address pointer|


