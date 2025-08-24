# DemandLib
[Git Source](https://github.com/Uniswap/twap-auction/blob/03b283c54c5f2efd695e0da42cae5de574a91cf7/src/libraries/DemandLib.sol)


## Functions
### resolve


```solidity
function resolve(Demand memory _demand, uint256 price, bool currencyIsToken0) internal pure returns (uint256);
```

### resolveCurrencyDemand

Resolve the currency demand at a price based on currencyIsToken0


```solidity
function resolveCurrencyDemand(uint256 amount, uint256 price, bool currencyIsToken0) internal pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|the demand in terms of `token`|


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

