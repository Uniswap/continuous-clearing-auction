# AuctionStepStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/0029089ebd1a3f788abcf4818f240d0f675068e6/src/AuctionStepStorage.sol)

**Inherits:**
[IAuctionStepStorage](/src/interfaces/IAuctionStepStorage.sol/interface.IAuctionStepStorage.md)

Abstract contract to store and read information about the auction issuance schedule


## State Variables
### UINT64_SIZE
The size of a uint64 in bytes


```solidity
uint256 public constant UINT64_SIZE = 8;
```


### startBlock
The block at which the auction starts


```solidity
uint64 public immutable startBlock;
```


### endBlock
The block at which the auction ends


```solidity
uint64 public immutable endBlock;
```


### _length
Cached length of the auction steps data provided in the constructor


```solidity
uint256 private immutable _length;
```


### $_pointer
The address pointer to the contract deployed by SSTORE2


```solidity
address private $_pointer;
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

