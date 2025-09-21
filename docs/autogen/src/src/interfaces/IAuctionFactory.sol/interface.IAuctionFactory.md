# IAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/4a2534467c505f9bb8c4a942d2cc4f01d7d061ef/src/interfaces/IAuctionFactory.sol)

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

