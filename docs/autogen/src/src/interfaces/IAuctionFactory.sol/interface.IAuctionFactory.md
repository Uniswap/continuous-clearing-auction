# IAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/e1dbf4f02e1bcbb91486a39f0f49eb2aeb52ecc6/src/interfaces/IAuctionFactory.sol)

**Inherits:**
[IDistributionStrategy](/src/interfaces/external/IDistributionStrategy.sol/interface.IDistributionStrategy.md)


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

