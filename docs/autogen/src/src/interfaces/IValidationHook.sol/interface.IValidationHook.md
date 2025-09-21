# IValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/interfaces/IValidationHook.sol)


## Functions
### validate

Validate a bid

*MUST revert if the bid is invalid*


```solidity
function validate(
    uint256 maxPrice,
    bool exactIn,
    uint128 amount,
    address owner,
    address sender,
    bytes calldata hookData
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`sender`|`address`|The sender of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|


