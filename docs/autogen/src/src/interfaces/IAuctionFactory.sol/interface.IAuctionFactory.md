# IAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/c759e43fae42070cf9e95f131465e97b1a9613f7/src/interfaces/IAuctionFactory.sol)

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

## Errors
### TotalSupplyOverUint128Max
Error thrown when the total supply is too large to fit in a uint128


```solidity
error TotalSupplyOverUint128Max();
```

