# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/69de3ae4ba8e1e42b571cd7d7900cef9574ede92/src/interfaces/IBidStorage.sol)


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

