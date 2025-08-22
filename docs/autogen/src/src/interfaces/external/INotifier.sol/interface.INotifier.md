# INotifier
[Git Source](https://github.com/Uniswap/twap-auction/blob/95d02e3e7495a7b877fb15da76e79ca2d28e1d25/src/interfaces/external/INotifier.sol)


## Functions
### notify

Notify the subscribers

*The schema is defined by the implementation, proper authorization checks must be done*


```solidity
function notify() external;
```

## Events
### SubscriberRegistered
Emitted when a subscriber is registered


```solidity
event SubscriberRegistered(address indexed subscriber);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`subscriber`|`address`|The address of the subscriber|

## Errors
### SubscriberIsZero
Error thrown when the subscriber is the zero address


```solidity
error SubscriberIsZero();
```

### CannotNotifyYet
Error thrown before notifyBlock


```solidity
error CannotNotifyYet();
```

