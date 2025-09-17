# ITokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/112a0fea9b4fad64c513488ce5945ab8f444c9ad/src/interfaces/ITokenCurrencyStorage.sol)


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
### TokenIsNativeCurrency
Error thrown when the token is the native currency


```solidity
error TokenIsNativeCurrency();
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

### FundsRecipientIsZero
Error thrown when the funds recipient is the zero address


```solidity
error FundsRecipientIsZero();
```

### OnlyFundsRecipient
Error thrown when the function is called by an address other than the funds recipient


```solidity
error OnlyFundsRecipient();
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

### InvalidGraduationThresholdMps
Error thrown when the graduation threshold is invalid


```solidity
error InvalidGraduationThresholdMps();
```

### NotGraduated
Error thrown when the auction has not graduated


```solidity
error NotGraduated();
```

### FundsRecipientCallFailed
Error thrown when the funds recipient data cannot be decoded


```solidity
error FundsRecipientCallFailed();
```

