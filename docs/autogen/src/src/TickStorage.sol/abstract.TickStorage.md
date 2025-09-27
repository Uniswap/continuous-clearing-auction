# TickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/0029089ebd1a3f788abcf4818f240d0f675068e6/src/TickStorage.sol)

**Inherits:**
[ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md)

Abstract contract for handling tick storage


## State Variables
### $_ticks

```solidity
mapping(uint256 price => Tick) private $_ticks;
```


### $nextActiveTickPrice
The price of the next initialized tick above the clearing price

*This will be equal to the clearingPrice if no ticks have been initialized yet*


```solidity
uint256 internal $nextActiveTickPrice;
```


### floorPrice
Get the floor price of the auction


```solidity
uint256 public immutable floorPrice;
```


### tickSpacing
Get the tick spacing enforced for bid prices


```solidity
uint256 public immutable tickSpacing;
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


### _updateTick

Internal function to add a bid to a tick and update its values

*Requires the tick to be initialized*


```solidity
function _updateTick(uint256 price, bool exactIn, uint128 amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint128`|The amount of the bid|


### nextActiveTickPrice

The price of the next initialized tick above the clearing price

*This will be equal to the clearingPrice if no ticks have been initialized yet*


```solidity
function nextActiveTickPrice() external view override(ITickStorage) returns (uint256);
```

### ticks

Get a tick at a price


```solidity
function ticks(uint256 price) external view override(ITickStorage) returns (Tick memory);
```

