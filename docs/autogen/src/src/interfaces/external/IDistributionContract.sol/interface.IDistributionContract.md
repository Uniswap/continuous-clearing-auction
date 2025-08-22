# IDistributionContract
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/interfaces/external/IDistributionContract.sol)

Interface for token distribution contracts.


## Functions
### onTokensReceived

Notify a distribution contract that it has received the tokens to distribute


```solidity
function onTokensReceived(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to be distributed.|
|`amount`|`uint256`|The amount of tokens intended for distribution.|


