# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/0ee04bc2c45f6d51f37030260f300f404e183bf7/src/interfaces/IBidStorage.sol)


## Functions
### nextBidId

Get the id of the next bid to be created


```solidity
function nextBidId() external view returns (uint256);
```

### bids

Get a bid from storage


```solidity
function bids(uint256 bidId) external view returns (Bid memory);
```

