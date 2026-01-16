# LBPInitializationParams
[Git Source](https://github.com/Uniswap/twap-auction/blob/949d1892c9cdad238344a57f13bea4cf1aa50924/src/interfaces/external/ILBPInitializer.sol)

General parameters for initializing an LBP strategy


```solidity
struct LBPInitializationParams {
uint256 initialPriceX96; // the price discovered by the contract
uint256 tokensSold; // the number of tokens sold by the contract
uint256 currencyRaised; // the amount of currency raised by the contract
}
```

