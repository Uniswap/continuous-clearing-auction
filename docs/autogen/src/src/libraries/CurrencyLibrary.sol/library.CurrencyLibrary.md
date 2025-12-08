# CurrencyLibrary
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/libraries/CurrencyLibrary.sol)

**Title:**
CurrencyLibrary

This library allows for transferring and holding native tokens and ERC20 tokens

Forked from https://github.com/Uniswap/v4-core/blob/main/src/types/Currency.sol but modified to not bubble up reverts


## State Variables
### ADDRESS_ZERO
A constant to represent the native currency


```solidity
Currency public constant ADDRESS_ZERO = Currency.wrap(address(0))
```


## Functions
### transfer


```solidity
function transfer(Currency currency, address to, uint256 amount) internal;
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

