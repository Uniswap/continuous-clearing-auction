# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/6b2a64d622a65a4559a5632b05010c0fa5d89278/src/libraries/DemandLib.sol)

Library for demand calculations and operations


## Functions
### resolve


```solidity
function resolve(Demand memory _demand, uint256 price) internal pure returns (uint128);
```

### resolveCurrencyDemand


```solidity
function resolveCurrencyDemand(uint128 amount, uint256 price) internal pure returns (uint128);
```

### sub


```solidity
function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### add


```solidity
function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### applyMps


```solidity
function applyMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory);
```

### addCurrencyAmount


```solidity
function addCurrencyAmount(Demand memory _demand, uint128 _amount) internal pure returns (Demand memory);
```

### addTokenAmount


```solidity
function addTokenAmount(Demand memory _demand, uint128 _amount) internal pure returns (Demand memory);
```

