# ITokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/ab88be10ec09bebb9ce21e524c265366917b5a1f/src/interfaces/ITokenCurrencyStorage.sol)

Interface for token and currency storage operations


## Functions
### currency

The currency being raised in the auction


```solidity
function currency() external view returns (Currency);
```

### token

The token being sold in the auction


```solidity
function token() external view returns (IERC20Minimal);
```

### totalSupply

The total supply of tokens to sell


```solidity
function totalSupply() external view returns (uint128);
```

### tokensRecipient

The recipient of any unsold tokens at the end of the auction


```solidity
function tokensRecipient() external view returns (address);
```

### fundsRecipient

The recipient of the raised Currency from the auction


```solidity
function fundsRecipient() external view returns (address);
```

## Events
### TokensSwept
Emitted when the tokens are swept


```solidity
event TokensSwept(address indexed tokensRecipient, uint256 tokensAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokensRecipient`|`address`|The address of the tokens recipient|
|`tokensAmount`|`uint256`|The amount of tokens swept|

### CurrencySwept
Emitted when the currency is swept


```solidity
event CurrencySwept(address indexed fundsRecipient, uint256 currencyAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fundsRecipient`|`address`|The address of the funds recipient|
|`currencyAmount`|`uint256`|The amount of currency swept|

## Errors
### TokenIsAddressZero
Error thrown when the token is the native currency


```solidity
error TokenIsAddressZero();
```

### TokenAndCurrencyCannotBeTheSame
Error thrown when the token and currency are the same


```solidity
error TokenAndCurrencyCannotBeTheSame();
```

### TotalSupplyIsZero
Error thrown when the total supply is zero


```solidity
error TotalSupplyIsZero();
```

### TotalSupplyIsTooLarge
Error thrown when the total supply is too large


```solidity
error TotalSupplyIsTooLarge();
```

### FundsRecipientIsZero
Error thrown when the funds recipient is the zero address


```solidity
error FundsRecipientIsZero();
```

### TokensRecipientIsZero
Error thrown when the tokens recipient is the zero address


```solidity
error TokensRecipientIsZero();
```

### CannotSweepCurrency
Error thrown when the currency cannot be swept


```solidity
error CannotSweepCurrency();
```

### CannotSweepTokens
Error thrown when the tokens cannot be swept


```solidity
error CannotSweepTokens();
```

### NotGraduated
Error thrown when the auction has not graduated


```solidity
error NotGraduated();
```

