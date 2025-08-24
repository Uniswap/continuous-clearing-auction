# ITickStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/549d4b926d52df765a1a4cf1e867f87f2df6825e/src/interfaces/ITickStorage.sol)

Interface for the TickStorage contract


## Events
### TickInitialized
Emitted when a tick is initialized


```solidity
event TickInitialized(uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|

### NextActiveTickUpdated
Emitted when the nextActiveTick is updated


```solidity
event NextActiveTickUpdated(uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`price`|`uint256`|The price of the tick|

## Errors
### TickPriceNotIncreasing
Error thrown when the tick price is not increasing


```solidity
error TickPriceNotIncreasing();
```

