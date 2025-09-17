# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/9b332e9ae711433b888783601b4b8b92cce6d905/src/TokenCurrencyStorage.sol)

**Inherits:**
[ITokenCurrencyStorage](/src/interfaces/ITokenCurrencyStorage.sol/interface.ITokenCurrencyStorage.md)


## State Variables
### currency
The currency being raised in the auction


```solidity
Currency public immutable currency;
```


### token
The token being sold in the auction


```solidity
IERC20Minimal public immutable token;
```


### totalSupply
The total supply of tokens to sell

*The auction does not support selling more than type(uint128).max tokens*


```solidity
uint128 public immutable totalSupply;
```


### tokensRecipient
The recipient of any unsold tokens at the end of the auction


```solidity
address public immutable tokensRecipient;
```


### fundsRecipient
The recipient of the raised Currency from the auction


```solidity
address public immutable fundsRecipient;
```


### graduationThresholdMps
The minimum percentage of the total supply that must be sold


```solidity
uint24 public immutable graduationThresholdMps;
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
    uint128 _totalSupply,
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

