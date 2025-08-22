# Notifier
[Git Source](https://github.com/Uniswap/twap-auction/blob/95d02e3e7495a7b877fb15da76e79ca2d28e1d25/src/Notifier.sol)

**Inherits:**
[INotifier](/src/interfaces/external/INotifier.sol/interface.INotifier.md)

Abstract contract for notifying subscribers of the auction results


## State Variables
### subscribers

```solidity
ISubscriber[] public subscribers;
```


### notifyBlock

```solidity
uint64 public notifyBlock;
```


## Functions
### constructor


```solidity
constructor(ISubscriber[] memory _subscribers, uint64 _notifyBlock);
```

### notify

Notify the subscribers

*The schema is defined by the implementation, proper authorization checks must be done*


```solidity
function notify() external virtual;
```

### _notify

Notify the subscribers of the auction results


```solidity
function _notify(uint256 priceX192, uint128 tokenAmount, uint128 currencyAmount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`priceX192`|`uint256`|The price in 192-bit fixed point format|
|`tokenAmount`|`uint128`|The amount of tokens to match with the currency raised at the price|
|`currencyAmount`|`uint128`|The amount of currency raised|


