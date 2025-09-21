# CurrencyLibrary
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/libraries/CurrencyLibrary.sol)

*This library allows for transferring and holding native tokens and ERC20 tokens*

*Forked from https://github.com/Uniswap/v4-core/blob/main/src/types/Currency.sol but modified to not bubble up reverts*


## State Variables
### ADDRESS_ZERO
A constant to represent the native currency


```solidity
Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));
```


## Functions
### transfer


```solidity
function transfer(Currency currency, address to, uint256 amount) internal;
```

### balanceOfSelf


```solidity
function balanceOfSelf(Currency currency) internal view returns (uint256);
```

### balanceOf


```solidity
function balanceOf(Currency currency, address owner) internal view returns (uint256);
```

### isAddressZero


```solidity
function isAddressZero(Currency currency) internal pure returns (bool);
```

## Errors
### NativeTransferFailed
Thrown when a native transfer fails


```solidity
error NativeTransferFailed();
```

### ERC20TransferFailed
Thrown when an ERC20 transfer fails


```solidity
error ERC20TransferFailed();
```

