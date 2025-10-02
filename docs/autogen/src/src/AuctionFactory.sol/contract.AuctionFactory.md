# AuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/AuctionFactory.sol)

**Inherits:**
[IAuctionFactory](/src/interfaces/IAuctionFactory.sol/interface.IAuctionFactory.md)


## Functions
### initializeDistribution

Initialize a distribution of tokens under this strategy.

*Contracts can choose to deploy an instance with a factory-model or handle all distributions within the
implementing contract. For some strategies this function will handle the entire distribution, for others it
could merely set up initial state and provide additional entrypoints to handle the distribution logic.*


```solidity
function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt)
    external
    returns (IDistributionContract distributionContract);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to be distributed.|
|`amount`|`uint256`|The amount of tokens intended for distribution.|
|`configData`|`bytes`|Arbitrary, strategy-specific parameters.|
|`salt`|`bytes32`|The salt to use for the deterministic deployment.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`distributionContract`|`IDistributionContract`|The contract that will handle or manage the distribution. (Could be `address(this)` if the strategy is handled in-place, or a newly deployed instance).|


### getAuctionAddress

Get the address of an auction contract


```solidity
function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt)
    public
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


