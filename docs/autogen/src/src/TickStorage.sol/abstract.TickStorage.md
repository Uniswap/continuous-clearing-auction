# TickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/60abcc13bc954ef69471e1981dc9965a554c3331/src/TickStorage.sol)

**Inherits:**
[ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md)

Abstract contract for handling tick storage


## State Variables
### ticks

```solidity
mapping(uint256 price => Tick) public ticks;
```


### nextActiveTickPrice
The price of the next initialized tick above the clearing price

*This will be equal to the clearingPrice if no ticks have been initialized yet*


```solidity
uint256 public nextActiveTickPrice;
```


### FLOOR_PRICE
The floor price of the auction


```solidity
uint256 internal immutable FLOOR_PRICE;
```


### TICK_SPACING
The tick spacing of the auction - bids must be placed at discrete tick intervals


```solidity
uint256 internal immutable TICK_SPACING;
```


### MAX_TICK_PRICE
Sentinel value for the next value of the highest tick in the book


```solidity
uint256 public constant MAX_TICK_PRICE = type(uint256).max;
```


## Functions
### constructor


```solidity
constructor(uint256 _tickSpacing, uint256 _floorPrice);
```

### getTick

Get a tick at a price

*The returned tick is not guaranteed to be initialized*


```solidity
function getTick(uint256 price) public view returns (Tick memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|


### _unsafeInitializeTick

Initialize a tick at `price` without checking for existing ticks

*This function is unsafe and should only be used when the tick is guaranteed to be the first in the book*


```solidity
function _unsafeInitializeTick(uint256 price) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|


### _initializeTickIfNeeded

Initialize a tick at `price` if it does not exist already

*Requires `prevId` to be the id of the tick immediately preceding the desired price
NextActiveTick will be updated if the new tick is right before it*


```solidity
function _initializeTickIfNeeded(uint256 prevPrice, uint256 price) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`prevPrice`|`uint256`|The price of the previous tick|
|`price`|`uint256`|The price of the tick|


### _updateTickDemand

Internal function to add demand to a tick


```solidity
function _updateTickDemand(uint256 price, Demand memory demand) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|
|`demand`|`Demand`|The demand to add|


### floorPrice

Get the floor price of the auction


```solidity
function floorPrice() external view override(ITickStorage) returns (uint256);
```

### tickSpacing

Get the tick spacing enforced for bid prices


```solidity
function tickSpacing() external view override(ITickStorage) returns (uint256);
```

