# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/ace0c8fa02a7f9ecc269c8d6adca532a0d0858dc/src/interfaces/IBidStorage.sol)


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

