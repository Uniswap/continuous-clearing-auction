# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/91c505699ed85a7d0194c9a8cabc334c99e11f9f/src/interfaces/IBidStorage.sol)


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

