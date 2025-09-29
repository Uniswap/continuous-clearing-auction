# IValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/07712f11fafad883cb4261b09b8cf07d1b82d868/src/interfaces/IValidationHook.sol)

Interface for custom bid validation logic


## Functions
### validate

Validate a bid

*MUST revert if the bid is invalid*


```solidity
function validate(
    uint256 maxPrice,
    bool exactIn,
    uint256 amount,
    address owner,
    address sender,
    bytes calldata hookData
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`exactIn`|`bool`|Whether the bid is exact in|
|`amount`|`uint256`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`sender`|`address`|The sender of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|


