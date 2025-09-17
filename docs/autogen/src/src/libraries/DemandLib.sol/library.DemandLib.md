# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/ce0cdcca7cbcb44361047d64c159d39b69b75e36/src/libraries/DemandLib.sol)


## Functions
### resolve


```solidity
function resolve(Demand memory _demand, uint256 price) internal pure returns (ValueX7);
```

### resolveCurrencyDemand


```solidity
function resolveCurrencyDemand(ValueX7 amount, uint256 price) internal pure returns (ValueX7);
```

### add


```solidity
function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### sub


```solidity
function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory);
```

### applyMps

Apply mps to demand

*Requires both currencyDemand and tokenDemand to be > MPS to avoid loss of precision*


```solidity
function applyMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory);
```

