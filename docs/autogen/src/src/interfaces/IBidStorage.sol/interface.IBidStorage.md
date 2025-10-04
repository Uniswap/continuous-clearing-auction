# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/4e79543472823ca4f19066f04f5392aba6563627/src/interfaces/IBidStorage.sol)


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

