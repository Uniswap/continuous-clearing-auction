# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/f8777e7fce735616b313ae1a2d98047cf7578018/src/libraries/DemandLib.sol)


## Functions
### resolve


```solidity
function resolve(Demand memory _demand, uint256 price) internal pure returns (uint128);
```

### resolveCurrencyDemand


```solidity
function resolveCurrencyDemand(uint128 amount, uint256 price) internal pure returns (uint128);
```

### resolveTokenDemand


```solidity
function resolveTokenDemand(uint128 amount) internal pure returns (uint128);
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

