# ITokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/f66249e6bb5ebf3be6698edff5f27719f8f33c6e/src/interfaces/ITokenCurrencyStorage.sol)


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
function totalSupply() external view returns (uint256);
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

### graduationThresholdMps

The minimum portion (in MPS) of the total supply that must be sold


```solidity
function graduationThresholdMps() external view returns (uint24);
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

