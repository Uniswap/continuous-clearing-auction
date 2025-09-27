# IAuctionStepStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/0029089ebd1a3f788abcf4818f240d0f675068e6/src/interfaces/IAuctionStepStorage.sol)


## Functions
### startBlock

The block at which the auction starts


```solidity
function startBlock() external view returns (uint64);
```

### endBlock

The block at which the auction ends


```solidity
function endBlock() external view returns (uint64);
```

### step

Get the current active auction step


```solidity
function step() external view returns (AuctionStep memory);
```

## Events
### AuctionStepRecorded
Emitted when an auction step is recorded


```solidity
event AuctionStepRecorded(uint256 indexed startBlock, uint256 indexed endBlock, uint24 mps);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startBlock`|`uint256`|The start block of the auction step|
|`endBlock`|`uint256`|The end block of the auction step|
|`mps`|`uint24`|The percentage of total tokens to sell per block during this auction step, represented in ten-millionths of the total supply (1e7 = 100%)|

## Errors
### InvalidPointer
Error thrown when the SSTORE2 pointer is the zero address


```solidity
error InvalidPointer();
```

### AuctionIsOver
Error thrown when the auction is over


```solidity
error AuctionIsOver();
```

### InvalidAuctionDataLength
Error thrown when the auction data length is invalid


```solidity
error InvalidAuctionDataLength();
```

### StepBlockDeltaCannotBeZero
Error thrown when the block delta in a step is zero


```solidity
error StepBlockDeltaCannotBeZero();
```

### InvalidMps
Error thrown when the mps is invalid


```solidity
error InvalidMps();
```

### InvalidEndBlock
Error thrown when the end block is invalid


```solidity
error InvalidEndBlock();
```

