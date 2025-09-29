# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/43737e6643fccd8bba6b520bad93b4c795de35b0/src/interfaces/IBidStorage.sol)


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

