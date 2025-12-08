# ITickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/interfaces/ITickStorage.sol)

**Title:**
ITickStorage

Interface for the TickStorage contract


## Functions
### nextActiveTickPrice

The price of the next initialized tick above the clearing price

This will be equal to the clearingPrice if no ticks have been initialized yet


```solidity
function nextActiveTickPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The price of the next active tick|


### floorPrice

Get the floor price of the auction


```solidity
function floorPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The minimum price for bids|


### tickSpacing

Get the tick spacing enforced for bid prices


```solidity
function tickSpacing() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tick spacing value|


### ticks

Get a tick at a price

The returned tick is not guaranteed to be initialized


```solidity
function ticks(uint256 price) external view returns (Tick memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick, which must be at a boundary designated by the tick spacing|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Tick`|The tick at the given price|


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
### TickSpacingTooSmall
Error thrown when the tick spacing is too small


```solidity
error TickSpacingTooSmall();
```

### FloorPriceIsZero
Error thrown when the floor price is zero


```solidity
error FloorPriceIsZero();
```

### FloorPriceTooLow
Error thrown when the floor price is below the minimum floor price


```solidity
error FloorPriceTooLow();
```

### TickPreviousPriceInvalid
Error thrown when the previous price hint is invalid (higher than the new price)


```solidity
error TickPreviousPriceInvalid();
```

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

### InvalidTickPrice
Error thrown when the tick price is invalid


```solidity
error InvalidTickPrice();
```

### CannotUpdateUninitializedTick
Error thrown when trying to update the demand of an uninitialized tick


```solidity
error CannotUpdateUninitializedTick();
```

