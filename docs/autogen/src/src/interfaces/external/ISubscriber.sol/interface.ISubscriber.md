# ISubscriber
[Git Source](https://github.com/Uniswap/twap-auction/blob/95d02e3e7495a7b877fb15da76e79ca2d28e1d25/src/interfaces/external/ISubscriber.sol)

Interface for the LBPStrategyBasic contract


## Functions
### setInitialPrice

Sets the initial price of the pool based on the auction results and transfers the currency to the contract


```solidity
function setInitialPrice(uint256 priceX192, uint128 tokenAmount, uint128 currencyAmount) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`priceX192`|`uint256`|The price of the pool in 192-bit fixed point format (2 ** 192 * price)|
|`tokenAmount`|`uint128`|The amount of tokens needed for that price|
|`currencyAmount`|`uint128`|The amount of currency needed for that price and transferred to the contract|


## Events
### InitialPriceSet
Emitted when the initial price is set


```solidity
event InitialPriceSet(uint256 priceX192, uint256 tokenAmount, uint256 currencyAmount);
```

## Errors
### OnlyAuctionCanSetPrice
Error thrown when caller is not the auction contract


```solidity
error OnlyAuctionCanSetPrice(address auction, address caller);
```

### InvalidCurrencyAmount
Error thrown when the currency amount transferred is invalid


```solidity
error InvalidCurrencyAmount(uint256 expected, uint256 received);
```

### NonETHCurrencyCannotReceiveETH
Error thrown when ETH is sent to the contract but the configured currency is not ETH (e.g. an ERC20 token)


```solidity
error NonETHCurrencyCannotReceiveETH(address currency);
```

### InvalidPrice
Error thrown when the price is invalid


```solidity
error InvalidPrice(uint256 price);
```

### InvalidLiquidity
Error thrown when the liquidity is invalid


```solidity
error InvalidLiquidity(uint128 maxLiquidityPerTick, uint128 liquidity);
```

### InvalidTokenAmount
Error thrown when the token amount is invalid


```solidity
error InvalidTokenAmount(uint128 tokenAmount, uint128 reserveSupply);
```

