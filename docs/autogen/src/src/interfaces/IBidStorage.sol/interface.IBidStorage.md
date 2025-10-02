# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/57168f679cba2e43cc601572a1c8354914505aab/src/interfaces/IBidStorage.sol)


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

