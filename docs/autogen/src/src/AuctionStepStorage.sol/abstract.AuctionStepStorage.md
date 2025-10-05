# AuctionStepStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/AuctionStepStorage.sol)

**Inherits:**
[IAuctionStepStorage](/src/interfaces/IAuctionStepStorage.sol/interface.IAuctionStepStorage.md)

Abstract contract to store and read information about the auction issuance schedule


## State Variables
### UINT64_SIZE
The size of a uint64 in bytes


```solidity
uint256 public constant UINT64_SIZE = 8;
```


### START_BLOCK
The block at which the auction starts


```solidity
uint64 internal immutable START_BLOCK;
```


### END_BLOCK
The block at which the auction ends


```solidity
uint64 internal immutable END_BLOCK;
```


### _LENGTH
Cached length of the auction steps data provided in the constructor


```solidity
uint256 internal immutable _LENGTH;
```


### $_pointer
The address pointer to the contract deployed by SSTORE2


```solidity
address private immutable $_pointer;
```


### $_offset
The word offset of the last read step in `auctionStepsData` bytes


```solidity
uint256 private $_offset;
```


### $step
The current active auction step


```solidity
AuctionStep internal $step;
```


## Functions
### constructor


```solidity
constructor(bytes memory _auctionStepsData, uint64 _startBlock, uint64 _endBlock);
```

### _validate

Validate the data provided in the constructor

*Checks that the contract was correctly deployed by SSTORE2 and that the total mps and blocks are valid*


```solidity
function _validate(address _pointer) private view;
```

### _advanceStep

Advance the current auction step

*This function is called on every new bid if the current step is complete*


```solidity
function _advanceStep() internal returns (AuctionStep memory);
```

### step

Get the current active auction step


```solidity
function step() external view override(IAuctionStepStorage) returns (AuctionStep memory);
```

### startBlock

The block at which the auction starts


```solidity
function startBlock() external view override(IAuctionStepStorage) returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The starting block number|


### endBlock

The block at which the auction ends


```solidity
function endBlock() external view override(IAuctionStepStorage) returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The ending block number|


### pointer

The address pointer to the contract deployed by SSTORE2


```solidity
function pointer() external view override(IAuctionStepStorage) returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address pointer|


