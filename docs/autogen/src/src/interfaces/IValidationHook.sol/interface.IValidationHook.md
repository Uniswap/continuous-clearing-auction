# IValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/ce0cdcca7cbcb44361047d64c159d39b69b75e36/src/interfaces/IValidationHook.sol)


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


