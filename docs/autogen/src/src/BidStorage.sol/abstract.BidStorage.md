# BidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/d1e7b82f3777bade51fea369dcee7819652c8bdc/src/BidStorage.sol)


## State Variables
### nextBidId
The id of the next bid to be created


```solidity
uint256 public nextBidId;
```


### bids
The mapping of bid ids to bids


```solidity
mapping(uint256 bidId => Bid bid) public bids;
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
function _createBid(bool exactIn, uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
    internal
    returns (Bid memory bid, uint256 bidId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`exactIn`|`bool`|Whether the bid is exact in|
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


