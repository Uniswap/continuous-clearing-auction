# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/c2dd0a6c704cd1292624039dee42341e0a61b05d/src/libraries/DemandLib.sol)


## Functions
### resolve


```solidity
function resolve(Demand memory _demand, uint256 price) internal pure returns (uint256);
```

### resolveCurrencyDemand


```solidity
function resolveCurrencyDemand(uint256 amount, uint256 price) internal pure returns (uint256);
```

### resolveTokenDemand


```solidity
function resolveTokenDemand(uint256 amount) internal pure returns (uint256);
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
function addCurrencyAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory);
```

### addTokenAmount


```solidity
function addTokenAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory);
```

