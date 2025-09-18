# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/9bec60d05856063c5da9028135f2966636758f1a/src/TokenCurrencyStorage.sol)

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


```solidity
uint256 public immutable totalSupply;
```


### totalSupplyX7
The total supply of tokens to sell, scaled up to a ValueX7

*The auction does not support selling more than type(uint256).max / MPSLib.MPS (1e7) tokens*


```solidity
ValueX7 internal immutable totalSupplyX7;
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
The minimum portion (in MPS) of the total supply that must be sold


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

