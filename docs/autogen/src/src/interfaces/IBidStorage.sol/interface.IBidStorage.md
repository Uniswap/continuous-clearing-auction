# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/0029089ebd1a3f788abcf4818f240d0f675068e6/src/interfaces/IBidStorage.sol)


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

