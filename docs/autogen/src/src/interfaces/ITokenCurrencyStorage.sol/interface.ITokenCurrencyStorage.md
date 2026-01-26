# ITokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/949d1892c9cdad238344a57f13bea4cf1aa50924/src/interfaces/ITokenCurrencyStorage.sol)

Interface for token and currency storage operations


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

