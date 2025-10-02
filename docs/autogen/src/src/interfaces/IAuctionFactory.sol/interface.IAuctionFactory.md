# IAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/interfaces/IAuctionFactory.sol)

**Inherits:**
[IDistributionStrategy](/src/interfaces/external/IDistributionStrategy.sol/interface.IDistributionStrategy.md)


## Functions
### getAuctionAddress

Get the address of an auction contract


```solidity
function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt)
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

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the auction contract|


## Events
### AuctionCreated
Emitted when an auction is created


```solidity
event AuctionCreated(address indexed auction, address token, uint256 amount, bytes configData);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`auction`|`address`|The address of the auction contract|
|`token`|`address`|The address of the token|
|`amount`|`uint256`|The amount of tokens to sell|
|`configData`|`bytes`|The configuration data for the auction|

