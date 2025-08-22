# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/a40941ed6c71ce668b5d7c2923b5830fe9b23869/src/libraries/DemandLib.sol)


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

### applyMpsDenominator


```solidity
function applyMpsDenominator(Demand memory _demand, uint24 mps, uint24 mpsDenominator)
    internal
    pure
    returns (Demand memory);
```

### addCurrencyAmount


```solidity
function addCurrencyAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory);
```

### addTokenAmount


```solidity
function addTokenAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory);
```

