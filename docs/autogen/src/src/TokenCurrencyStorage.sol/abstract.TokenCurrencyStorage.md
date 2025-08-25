# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/8f0cdceab8341bbaf5daef9ba1cd7a3cb87561d1/src/TokenCurrencyStorage.sol)

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


### fundsRecipientDeadlineBlock
The block at which the Currency must be swept by the funds recipient


```solidity
uint64 public immutable fundsRecipientDeadlineBlock;
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
    uint256 _totalSupply,
    address _tokensRecipient,
    address _fundsRecipient,
    uint64 _fundsRecipientDeadlineBlock,
    uint24 _graduationThresholdMps
);
```

### _isGraduated

Whether the auction has graduated (sold more than the graduation threshold)

*Should only be called after the auction has ended*


```solidity
function _isGraduated(uint256 _totalCleared) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_totalCleared`|`uint256`|The total amount of tokens cleared, must be the final checkpoint of the auction|


### _canSweepCurrency

*The currency can only be swept if they have not been already, and before the deadline for sweeping tokens has passed*


```solidity
function _canSweepCurrency() internal view returns (bool);
```

### _sweepCurrency


```solidity
function _sweepCurrency(uint256 amount) internal;
```

### _sweepUnsoldTokens


```solidity
function _sweepUnsoldTokens(uint256 amount) internal;
```

