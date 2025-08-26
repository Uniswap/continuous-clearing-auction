# AuctionFactory
[Git Source](https://github.com/Uniswap/twap-auction/blob/da50bb7a07b27dca661d22f04fb3c44d8922d9da/src/AuctionFactory.sol)

**Inherits:**
[IAuctionFactory](/src/interfaces/IAuctionFactory.sol/interface.IAuctionFactory.md)


## State Variables
### USE_MSG_SENDER

```solidity
address public constant USE_MSG_SENDER = 0x0000000000000000000000000000000000000001;
```


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


