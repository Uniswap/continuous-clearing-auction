# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/6199a07349a5d22f79f49db95ea478090bd8c68d/src/interfaces/IBidStorage.sol)


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

