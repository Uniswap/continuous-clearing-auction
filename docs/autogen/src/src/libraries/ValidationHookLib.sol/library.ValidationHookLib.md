# ValidationHookLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/libraries/ValidationHookLib.sol)

Library for handling calls to validation hooks and bubbling up the revert reason


## Functions
### handleValidate

Handles calling a validation hook and bubbling up the revert reason


```solidity
function handleValidate(
    IValidationHook hook,
    uint256 maxPrice,
    uint256 amount,
    address owner,
    address sender,
    bytes calldata hookData
) internal;
```

## Errors
### ValidationHookCallFailed
Error thrown when a validation hook call fails


```solidity
error ValidationHookCallFailed(bytes reason);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`reason`|`bytes`|The bubbled up revert reason|

