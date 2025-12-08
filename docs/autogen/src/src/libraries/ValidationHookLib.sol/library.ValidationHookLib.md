# ValidationHookLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/ValidationHookLib.sol)

**Title:**
ValidationHookLib

Library for handling calls to validation hooks and bubbling up the revert reason


## Functions
### handleValidate

Handles calling a validation hook and bubbling up the revert reason


```solidity
function handleValidate(
    IValidationHook hook,
    uint256 maxPrice,
    uint128 amount,
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

