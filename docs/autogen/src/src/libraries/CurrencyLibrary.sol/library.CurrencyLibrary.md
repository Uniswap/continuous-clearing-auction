# CurrencyLibrary
[Git Source](https://github.com/Uniswap/twap-auction/blob/046dab769f5d2ea2e8b9bef5d784a4e50afa7ccd/src/libraries/CurrencyLibrary.sol)

*This library allows for transferring and holding native tokens and ERC20 tokens*

*Forked from https://github.com/Uniswap/v4-core/blob/main/src/types/Currency.sol*

*Modified to not bubble up reverts and removed unused functions*


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

