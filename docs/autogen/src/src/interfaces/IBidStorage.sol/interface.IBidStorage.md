# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/cfe064d2fdebcf6b4861fcd47553d75e33aa20ae/src/interfaces/IBidStorage.sol)


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

