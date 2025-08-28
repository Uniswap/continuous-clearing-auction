# IAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/1c5771863c4021bfedcc36824eaa17f627dc43e0/src/interfaces/IAuctionFactory.sol)

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

