# IDistributionStrategy
[Git Source](https://github.com/Uniswap/twap-auction/blob/f955567475dc7cb036aa7f88109eaf0e5c68f43d/src/interfaces/external/IDistributionStrategy.sol)

Interface for token distribution strategies.


## Functions
### getAddressesAndAmounts


```solidity
function getAddressesAndAmounts(address token, uint256 amount, bytes calldata configData, bytes32 salt)
    external
    view
    returns (address[] memory, uint256[] memory);
```

### initializeDistribution

Initialize a distribution of tokens under this strategy.

*Contracts can choose to deploy an instance with a factory-model or handle all distributions within the
implementing contract. For some strategies this function will handle the entire distribution, for others it
could merely set up initial state and provide additional entrypoints to handle the distribution logic.*


```solidity
function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to be distributed.|
|`amount`|`uint256`|The amount of tokens intended for distribution.|
|`configData`|`bytes`|Arbitrary, strategy-specific parameters.|
|`salt`|`bytes32`|The salt to use for the deterministic deployment.|


