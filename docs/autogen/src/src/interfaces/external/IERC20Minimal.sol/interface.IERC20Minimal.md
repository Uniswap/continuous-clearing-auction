# IERC20Minimal
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/interfaces/external/IERC20Minimal.sol)

Minimal ERC20 interface


## Functions
### balanceOf

Returns an account's balance in the token


```solidity
function balanceOf(address account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The account for which to look up the number of tokens it has, i.e. its balance|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of tokens held by the account|


### transfer

Transfers the amount of token from the `msg.sender` to the recipient


```solidity
function transfer(address recipient, uint256 amount) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|The account that will receive the amount transferred|
|`amount`|`uint256`|The number of tokens to send from the sender to the recipient|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Returns true for a successful transfer, false for an unsuccessful transfer|


