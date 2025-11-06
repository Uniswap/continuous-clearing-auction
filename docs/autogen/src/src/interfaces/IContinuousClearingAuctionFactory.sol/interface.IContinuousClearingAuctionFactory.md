# IContinuousClearingAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/b4d0a06daced32c81e0487f3201e863948da89b2/src/interfaces/IContinuousClearingAuctionFactory.sol)

**Inherits:**
[IDistributionStrategy](/Users/eric.zhong/uniswap/twap-auction/docs/autogen/src/src/interfaces/external/IDistributionStrategy.sol/interface.IDistributionStrategy.md)


## Functions
### getAuctionAddress

Get the address of an auction contract


```solidity
function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
    external
    view
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token|
|`amount`|`uint256`|The amount of tokens to sell|
|`configData`|`bytes`|The configuration data for the auction|
|`salt`|`bytes32`|The salt to use for the deterministic deployment|
|`sender`|`address`|The sender of the initializeDistribution transaction|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the auction contract|


## Events
### AuctionCreated
Emitted when an auction is created


```solidity
event AuctionCreated(address indexed auction, address indexed token, uint256 amount, bytes configData);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`auction`|`address`|The address of the auction contract|
|`token`|`address`|The address of the token|
|`amount`|`uint256`|The amount of tokens to sell|
|`configData`|`bytes`|The configuration data for the auction|

## Errors
### InvalidTokenAmount
Error thrown when the amount is invalid


```solidity
error InvalidTokenAmount(uint256 amount);
```

