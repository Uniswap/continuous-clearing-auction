# AuctionStateLens
[Git Source](https://github.com/Uniswap/twap-auction/blob/000be74c9fb6e92005b3e6aff5f612cf221eaa8e/src/lens/AuctionStateLens.sol)

**Title:**
AuctionStateLens

Lens contract for reading the state of the Auction contract


## Functions
### state

Function which can be called from offchain to get the latest state of the auction


```solidity
function state(IContinuousClearingAuction auction) external returns (AuctionState memory);
```

### revertWithState

Function which checkpoints the auction, gets global values and encodes them into a revert string


```solidity
function revertWithState(IContinuousClearingAuction auction) external;
```

### parseRevertReason

Function which parses the revert reason and returns the AuctionState


```solidity
function parseRevertReason(bytes memory reason) internal pure returns (AuctionState memory);
```

## Errors
### CheckpointFailed
Error thrown when the checkpoint fails


```solidity
error CheckpointFailed();
```

### InvalidRevertReasonLength
Error thrown when the revert reason is not the correct length


```solidity
error InvalidRevertReasonLength();
```

