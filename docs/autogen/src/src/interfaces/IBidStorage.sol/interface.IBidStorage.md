# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/93c0c780ed33d07191c07fe0752db1c29bbcb8f7/src/interfaces/IBidStorage.sol)


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

## Errors
### BidIdDoesNotExist
Error thrown when doing an operation on a bid that does not exist


```solidity
error BidIdDoesNotExist();
```

