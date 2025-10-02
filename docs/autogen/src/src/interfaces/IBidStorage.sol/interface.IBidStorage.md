# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/68d18000c60b2a641f136e527165de89b151504d/src/interfaces/IBidStorage.sol)


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

