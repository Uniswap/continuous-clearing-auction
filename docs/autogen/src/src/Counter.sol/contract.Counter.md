# Counter
[Git Source](https://github.com/Uniswap/foundry-template/blob/0864bd3fda3ae2b97362ae80691cd59ca9cf5090/src/Counter.sol)

**Inherits:**
[ICounter](/src/interfaces/ICounter.sol/interface.ICounter.md)


## State Variables
### number

```solidity
uint256 public number;
```


## Functions
### constructor


```solidity
constructor(uint256 initialNumber);
```

### setNumber

Sets the number


```solidity
function setNumber(uint256 newNumber) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newNumber`|`uint256`|The new number|


### increment

Increments the number by 1


```solidity
function increment() public;
```

