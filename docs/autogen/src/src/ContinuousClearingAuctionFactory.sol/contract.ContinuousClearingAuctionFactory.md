# ContinuousClearingAuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/ContinuousClearingAuctionFactory.sol)

**Inherits:**
[IContinuousClearingAuctionFactory](/src/interfaces/IContinuousClearingAuctionFactory.sol/interface.IContinuousClearingAuctionFactory.md)

**Title:**
ContinuousClearingAuctionFactory

**Note:**
security-contact: security@uniswap.org


## Functions
### initializeDistribution

Initialize a distribution of tokens under this strategy.

Contracts can choose to deploy an instance with a factory-model or handle all distributions within the
implementing contract. For some strategies this function will handle the entire distribution, for others it
could merely set up initial state and provide additional entrypoints to handle the distribution logic.


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


