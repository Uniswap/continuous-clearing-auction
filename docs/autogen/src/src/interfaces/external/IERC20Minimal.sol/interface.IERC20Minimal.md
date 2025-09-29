# IERC20Minimal
[Git Source](https://github.com/Uniswap/twap-auction/blob/eddb06d9f9e6a95363d90d7326e355d98c8b0712/src/interfaces/external/IERC20Minimal.sol)

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


### approve

Approves the spender to spend the amount of tokens from the `msg.sender`


```solidity
function approve(address spender, uint256 amount) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`spender`|`address`|The account that will be allowed to spend the amount|
|`amount`|`uint256`|The number of tokens to allow the spender to spend|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Returns true for a successful approval, false for an unsuccessful approval|


