# ILBPInitializer
[Git Source](https://github.com/Uniswap/twap-auction/blob/949d1892c9cdad238344a57f13bea4cf1aa50924/src/interfaces/external/ILBPInitializer.sol)

**Inherits:**
[IDistributionContract](/src/interfaces/external/IDistributionContract.sol/interface.IDistributionContract.md), IERC165

**Title:**
ILBPInitializer

Generic interface for contracts used for initializing an LBP strategy


## Functions
### lbpInitializationParams

Returns the LBP initialization parameters as determined by the implementing contract

The implementing contract MUST ensure that these values are correct at the time of calling


```solidity
function lbpInitializationParams() external view returns (LBPInitializationParams memory params);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`params`|`LBPInitializationParams`|The LBP initialization parameters|


### token

Returns the token used by the initializer


```solidity
function token() external view returns (address);
```

### currency

Returns the currency used by the initializer


```solidity
function currency() external view returns (address);
```

### totalSupply

Returns the total supply of the token used by the initializer


```solidity
function totalSupply() external view returns (uint128);
```

### tokensRecipient

Returns the address which will receive the unsold tokens


```solidity
function tokensRecipient() external view returns (address);
```

### fundsRecipient

Returns the address which will receive the raised currency


```solidity
function fundsRecipient() external view returns (address);
```

### startBlock

Returns the start block of the initializer


```solidity
function startBlock() external view returns (uint64);
```

### endBlock

Returns the end block of the initializer


```solidity
function endBlock() external view returns (uint64);
```

