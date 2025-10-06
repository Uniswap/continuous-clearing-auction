# ITickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/1a7f98b9e1cb9ed630b15a7f62d113994de8c338/src/interfaces/ITickStorage.sol)

Interface for the TickStorage contract


## Functions
### getTick

Get a tick at a price

*The returned tick is not guaranteed to be initialized*


```solidity
function getTick(uint256 price) external view returns (Tick memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Tick`|The tick at the given price|


### nextActiveTickPrice

The price of the next initialized tick above the clearing price

*This will be equal to the clearingPrice if no ticks have been initialized yet*


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


```solidity
function ticks(uint256 price) external view returns (Tick memory);
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
### FloorPriceAboveMaxBidPrice
Error thrown when the floor price is above the maximum bid price


```solidity
error FloorPriceAboveMaxBidPrice();
```

### TickSpacingIsZero
Error thrown when the tick spacing is zero


```solidity
error TickSpacingIsZero();
```

### FloorPriceIsZero
Error thrown when the floor price is zero


```solidity
error FloorPriceIsZero();
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

