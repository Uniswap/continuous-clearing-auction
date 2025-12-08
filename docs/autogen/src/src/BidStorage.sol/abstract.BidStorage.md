# BidStorage
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/BidStorage.sol)

**Inherits:**
[IBidStorage](/src/interfaces/IBidStorage.sol/interface.IBidStorage.md)

Abstract contract for managing bid storage


## State Variables
### $_nextBidId
The id of the next bid to be created


```solidity
uint256 private $_nextBidId
```


### $_bids
The mapping of bid ids to bids


```solidity
mapping(uint256 bidId => Bid bid) private $_bids
```


## Functions
### _getBid

Get a bid from storage


```solidity
function _getBid(uint256 bidId) internal view returns (Bid storage);
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


### nextBidId

Getters


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


