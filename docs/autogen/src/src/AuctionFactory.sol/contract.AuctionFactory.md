# AuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/AuctionFactory.sol)

**Inherits:**
[IAuctionFactory](/src/interfaces/IAuctionFactory.sol/interface.IAuctionFactory.md)


## Functions
### initializeDistribution

Initialize a distribution of tokens under this strategy.

*Contracts can choose to deploy an instance with a factory-model or handle all distributions within the
implementing contract. For some strategies this function will handle the entire distribution, for others it
could merely set up initial state and provide additional entrypoints to handle the distribution logic.*


```solidity
function initializeDistribution(address token, uint256 amount, bytes calldata configData)
    external
    returns (IDistributionContract distributionContract);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to be distributed.|
|`amount`|`uint256`|The amount of tokens intended for distribution.|
|`configData`|`bytes`|Arbitrary, strategy-specific parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`distributionContract`|`IDistributionContract`|The contract that will handle or manage the distribution. (Could be `address(this)` if the strategy is handled in-place, or a newly deployed instance).|


