# ValidationHookLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/112a0fea9b4fad64c513488ce5945ab8f444c9ad/src/libraries/ValidationHookLib.sol)

Library for handling calls to validation hooks and bubbling up the revert reason


## Functions
### handleValidate

Handles calling a validation hook and bubbling up the revert reason


```solidity
function handleValidate(
    IValidationHook hook,
    uint256 maxPrice,
    bool exactIn,
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

