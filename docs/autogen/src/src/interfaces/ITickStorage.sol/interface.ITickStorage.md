# ITickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/381b0ae668f577856bcecaebacb52bec6c71bf17/src/interfaces/ITickStorage.sol)

Interface for the TickStorage contract


## Functions
### nextActiveTickPrice

The price of the next initialized tick above the clearing price

*This will be equal to the clearingPrice if no ticks have been initialized yet*


```solidity
function nextActiveTickPrice() external view returns (uint256);
```

### floorPrice

Get the floor price of the auction


```solidity
function floorPrice() external view returns (uint256);
```

### tickSpacing

Get the tick spacing enforced for bid prices


```solidity
function tickSpacing() external view returns (uint256);
```

## Events
### TickInitialized
Emitted when a tick is initialized


```solidity
event TickInitialized(uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|

### NextActiveTickUpdated
Emitted when the nextActiveTick is updated


```solidity
event NextActiveTickUpdated(uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|

## Errors
### TickPriceNotIncreasing
Error thrown when the tick price is not increasing


```solidity
error TickPriceNotIncreasing();
```

### TickPriceNotAtBoundary
Error thrown when the price is not at a boundary designated by the tick spacing


```solidity
error TickPriceNotAtBoundary();
```

