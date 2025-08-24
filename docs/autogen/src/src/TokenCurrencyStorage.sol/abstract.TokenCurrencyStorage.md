# TokenCurrencyStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/754a9fd70af9e184d49edc120bb93866e5543890/src/TokenCurrencyStorage.sol)

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


### currencyIsToken0
Whether the currency is sorted before the token in the auction

*If true, then currency is token0 and token is token1. Vice versa if false.*


```solidity
bool public immutable currencyIsToken0;
```


## Functions
### constructor


```solidity
constructor(address _token, address _currency, uint256 _totalSupply, address _tokensRecipient, address _fundsRecipient);
```

### _toPrice

Converts two amounts into a price

*Price is always expressed as token1 / token0*


```solidity
function _toPrice(uint256 currencyAmount, uint256 tokenAmount) internal view returns (uint256);
```

### _priceStrictlyBefore

Returns true if price1 is strictly ordered before price2

*Prices will be monotonically increasing or decreasing depending on the currency/token order
This function returns true if price1 would come before price2 in that order*


```solidity
function _priceStrictlyBefore(uint256 price1, uint256 price2) internal view returns (bool);
```

### _priceBeforeOrEqual

Returns true if price1 is ordered before or equal to price2

*Prices will be monotonically increasing or decreasing depending on the currency/token order
This function returns true if price1 would come before or equal to price2 in that order*


```solidity
function _priceBeforeOrEqual(uint256 price1, uint256 price2) internal view returns (bool);
```

### _priceStrictlyAfter

Returns true if price1 is strictly ordered after price2

*Prices will be monotonically increasing or decreasing depending on the currency/token order
This function returns true if price1 would come after price2 in that order*


```solidity
function _priceStrictlyAfter(uint256 price1, uint256 price2) internal view returns (bool);
```

### _priceAfterOrEqual

Returns true if price1 is ordered after or equal to price2

*Prices will be monotonically increasing or decreasing depending on the currency/token order
This function returns true if price1 would come after or equal to price2 in that order*


```solidity
function _priceAfterOrEqual(uint256 price1, uint256 price2) internal view returns (bool);
```

