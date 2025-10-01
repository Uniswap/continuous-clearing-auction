# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/f53d7155325c22ef28d878c4d9443735141b48d7/src/interfaces/IBidStorage.sol)


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

