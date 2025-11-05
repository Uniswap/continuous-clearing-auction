# IBidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/468d53629b7c1620881cec3814c348b60ec958e9/src/interfaces/IBidStorage.sol)

Interface for bid storage operations


## Functions
### nextBidId

Get the id of the next bid to be created


```solidity
function nextBidId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The id of the next bid to be created|


### bids

Get a bid from storage

Will revert if the bid does not exist


```solidity
function bids(uint256 bidId) external view returns (Bid memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Bid`|The bid|


## Errors
### BidIdDoesNotExist
Error thrown when doing an operation on a bid that does not exist


```solidity
error BidIdDoesNotExist(uint256 bidId);
```

