# ITokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/d3b547d57209cfb3e96b83f2eaf1cb01b89692c4/src/interfaces/ITokenCurrencyStorage.sol)


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

