# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/TokenCurrencyStorage.sol)

**Inherits:**
[ITokenCurrencyStorage](/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md)

**Title:**
TokenCurrencyStorage


## State Variables
### CURRENCY
The currency being raised in the auction


```solidity
Currency internal immutable CURRENCY
```


### TOKEN
The token being sold in the auction


```solidity
IERC20Minimal internal immutable TOKEN
```


### TOTAL_SUPPLY
The total supply of tokens to sell


```solidity
uint128 internal immutable TOTAL_SUPPLY
```


### TOKENS_RECIPIENT
The recipient of any unsold tokens at the end of the auction


```solidity
address internal immutable TOKENS_RECIPIENT
```


### FUNDS_RECIPIENT
The recipient of the raised Currency from the auction


```solidity
address internal immutable FUNDS_RECIPIENT
```


### REQUIRED_CURRENCY_RAISED_Q96_X7
The amount of currency required to be raised for the auction
to graduate in Q96 form, scaled up by X7


```solidity
ValueX7 internal immutable REQUIRED_CURRENCY_RAISED_Q96_X7
```


### sweepCurrencyBlock
The block at which the currency was swept


```solidity
uint256 public sweepCurrencyBlock
```


### sweepUnsoldTokensBlock
The block at which the tokens were swept


```solidity
uint256 public sweepUnsoldTokensBlock
```


## Functions
### constructor


```solidity
constructor(
    address _token,
    address _currency,
    uint128 _totalSupply,
    address _tokensRecipient,
    address _fundsRecipient,
    uint128 _requiredCurrencyRaised
) ;
```

### _sweepCurrency


```solidity
function _sweepCurrency(uint256 _blockNumberIsh, uint256 _amount) internal;
```

### _sweepUnsoldTokens


```solidity
function _sweepUnsoldTokens(uint256 _blockNumberIsh, uint256 _amount) internal;
```

