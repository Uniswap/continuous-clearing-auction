# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/4c9af76a705eb813cc2e0ec768b3771f7a342ec1/src/libraries/DemandLib.sol)


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

