# TickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/TickStorage.sol)

**Inherits:**
[ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md)

**Title:**
TickStorage

Abstract contract for handling tick storage


## State Variables
### $_ticks
Mapping of price levels to tick data


```solidity
mapping(uint256 price => Tick) private $_ticks
```


### $nextActiveTickPrice
The price of the next initialized tick above the clearing price

This will be equal to the clearingPrice if no ticks have been initialized yet


```solidity
uint256 internal $nextActiveTickPrice
```


### FLOOR_PRICE
The floor price of the auction


```solidity
uint256 internal immutable FLOOR_PRICE
```


### TICK_SPACING
The tick spacing of the auction - bids must be placed at discrete tick intervals


```solidity
uint256 internal immutable TICK_SPACING
```


### MAX_TICK_PTR
Sentinel value for the next pointer of the highest tick in the book


```solidity
uint256 public constant MAX_TICK_PTR = type(uint256).max
```


## Functions
### constructor


```solidity
constructor(uint256 _tickSpacing, uint256 _floorPrice) ;
```

### _getTick

Internal function to get a tick at a price

The returned tick is not guaranteed to be initialized


```solidity
function _getTick(uint256 price) internal view returns (Tick storage);
```

### _initializeTickIfNeeded

Initialize a tick at `price` if it does not exist already

`prevPrice` MUST be the price of an initialized tick before the new price.
Ideally, it is the price of the tick immediately preceding the desired price. If not,
we will iterate through the ticks until we find the next price which requires more gas.
If `price` is < `nextActiveTickPrice`, then `price` will be set as the nextActiveTickPrice


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
function _updateTickDemand(uint256 price, uint256 currencyDemandQ96) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|
|`currencyDemandQ96`|`uint256`|The demand to add|


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


