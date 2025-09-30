# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/07712f11fafad883cb4261b09b8cf07d1b82d868/src/TokenCurrencyStorage.sol)

**Inherits:**
[ITokenCurrencyStorage](/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md)


## State Variables
### CURRENCY
The currency being raised in the auction


```solidity
Currency internal immutable CURRENCY;
```


### TOKEN
The token being sold in the auction


```solidity
IERC20Minimal internal immutable TOKEN;
```


### TOTAL_SUPPLY
The total supply of tokens to sell


```solidity
uint256 internal immutable TOTAL_SUPPLY;
```


### TOTAL_SUPPLY_X7_X7
The total supply of tokens to sell, scaled up to a ValueX7X7


```solidity
ValueX7X7 internal immutable TOTAL_SUPPLY_X7_X7;
```


### TOKENS_RECIPIENT
The recipient of any unsold tokens at the end of the auction


```solidity
address internal immutable TOKENS_RECIPIENT;
```


### FUNDS_RECIPIENT
The recipient of the raised Currency from the auction


```solidity
address internal immutable FUNDS_RECIPIENT;
```


### GRADUATION_THRESHOLD_MPS
The minimum portion (in MPS) of the total supply that must be sold


```solidity
uint24 internal immutable GRADUATION_THRESHOLD_MPS;
```


### REQUIRED_SUPPLY_SOLD_FOR_GRADUATION_X7_X7
The amount of supply that must be sold for the auction to graduate, saved for gas optimization


```solidity
ValueX7X7 internal immutable REQUIRED_SUPPLY_SOLD_FOR_GRADUATION_X7_X7;
```


### sweepCurrencyBlock
The block at which the currency was swept


```solidity
uint256 public sweepCurrencyBlock;
```


### sweepUnsoldTokensBlock
The block at which the tokens were swept


```solidity
uint256 public sweepUnsoldTokensBlock;
```


## Functions
### constructor


```solidity
constructor(
    address _token,
    address _currency,
    uint256 _totalSupply,
    address _tokensRecipient,
    address _fundsRecipient,
    uint24 _graduationThresholdMps
);
```

### _sweepCurrency


```solidity
function _sweepCurrency(uint256 amount) internal;
```

### _sweepUnsoldTokens


```solidity
function _sweepUnsoldTokens(uint256 amount) internal;
```

### currency

The currency being raised in the auction


```solidity
function currency() external view override(ITokenCurrencyStorage) returns (Currency);
```

### token

The token being sold in the auction


```solidity
function token() external view override(ITokenCurrencyStorage) returns (IERC20Minimal);
```

### totalSupply

The total supply of tokens to sell


```solidity
function totalSupply() external view override(ITokenCurrencyStorage) returns (uint256);
```

### tokensRecipient

The recipient of any unsold tokens at the end of the auction


```solidity
function tokensRecipient() external view override(ITokenCurrencyStorage) returns (address);
```

### fundsRecipient

The recipient of the raised Currency from the auction


```solidity
function fundsRecipient() external view override(ITokenCurrencyStorage) returns (address);
```

### graduationThresholdMps

The minimum portion (in MPS) of the total supply that must be sold


```solidity
function graduationThresholdMps() external view override(ITokenCurrencyStorage) returns (uint24);
```

