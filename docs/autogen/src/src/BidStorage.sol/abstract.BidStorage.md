# BidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/BidStorage.sol)

**Inherits:**
[IBidStorage](/src/interfaces/IBidStorage.sol/interface.IBidStorage.md)

Abstract contract for managing bid storage


## State Variables
### $_nextBidId
The id of the next bid to be created


```solidity
uint256 private $_nextBidId;
```


### $_bids
The mapping of bid ids to bids


```solidity
mapping(uint256 bidId => Bid bid) private $_bids;
```


## Functions
### _getBid

Get a bid from storage


```solidity
function _getBid(uint256 bidId) internal view returns (Bid memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Bid`|bid The bid|


### _createBid

Create a new bid


```solidity
function _createBid(uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
    internal
    returns (Bid memory bid, uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`maxPrice`|`uint256`|The maximum price for the bid|
|`startCumulativeMps`|`uint24`|The cumulative mps at the start of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bid`|`Bid`|The created bid|
|`bidId`|`uint256`|The id of the created bid|


### _updateBid

Update a bid in storage


```solidity
function _updateBid(uint256 bidId, Bid memory bid) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid to update|
|`bid`|`Bid`|The new bid|


### _deleteBid

Delete a bid from storage


```solidity
function _deleteBid(uint256 bidId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid to delete|


### nextBidId

Getters


```solidity
function nextBidId() external view override(IBidStorage) returns (uint256);
```

### bids

Get a bid from storage


```solidity
function bids(uint256 bidId) external view override(IBidStorage) returns (Bid memory);
```

