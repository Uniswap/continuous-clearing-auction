# TickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/03b283c54c5f2efd695e0da42cae5de574a91cf7/src/TickStorage.sol)

**Inherits:**
[TokenCurrencyStorage](/src/TokenCurrencyStorage.sol/abstract.TokenCurrencyStorage.md), [ITickStorage](/src/interfaces/ITickStorage.sol/interface.ITickStorage.md)

Abstract contract for handling tick storage


## State Variables
### ticks

```solidity
mapping(uint256 price => Tick) public ticks;
```


### nextActiveTickPrice
The price of the next initialized tick above or below the clearing price, depending on currency/token order

*This will be equal to the clearingPrice if no ticks have been initialized yet*


```solidity
uint256 public nextActiveTickPrice;
```


### tickSpacing
The tick spacing enforced for bid prices


```solidity
uint256 public immutable tickSpacing;
```


### floorPrice
The starting price of the auction


```solidity
uint256 public immutable floorPrice;
```


### MAX_TICK_PRICE
Sentinel value for the next value of the highest tick in the book


```solidity
uint256 public constant MAX_TICK_PRICE = type(uint256).max;
```


### MIN_TICK_PRICE
Sentinel value for the next value of the lowest tick in the book


```solidity
uint256 public constant MIN_TICK_PRICE = 1;
```


## Functions
### constructor


```solidity
constructor(
    address _token,
    address _currency,
    uint256 _totalSupply,
    address _tokensRecipient,
    address _fundsRecipient,
    uint256 _tickSpacing,
    uint256 _floorPrice
) TokenCurrencyStorage(_token, _currency, _totalSupply, _tokensRecipient, _fundsRecipient);
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
function _updateTick(uint256 price, bool exactIn, uint256 amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|


