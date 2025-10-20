# Auction
[Git Source](https://github.com/Uniswap/twap-auction/blob/93c0c780ed33d07191c07fe0752db1c29bbcb8f7/src/Auction.sol)

**Inherits:**
[BidStorage](/src/BidStorage.sol/abstract.BidStorage.md), [CheckpointStorage](/src/CheckpointStorage.sol/abstract.CheckpointStorage.md), [AuctionStepStorage](/src/AuctionStepStorage.sol/abstract.AuctionStepStorage.md), [TickStorage](/src/TickStorage.sol/abstract.TickStorage.md), [PermitSingleForwarder](/src/PermitSingleForwarder.sol/abstract.PermitSingleForwarder.md), [TokenCurrencyStorage](/src/TokenCurrencyStorage.sol/abstract.TokenCurrencyStorage.md), [IAuction](/src/interfaces/IAuction.sol/interface.IAuction.md)

Implements a time weighted uniform clearing price auction

*Can be constructed directly or through the AuctionFactory. In either case, users must validate
that the auction parameters are correct and it has sufficient token balance.*

**Note:**
security-contact: security@uniswap.org


## State Variables
### MAX_BID_PRICE
The maximum price which a bid can be submitted at

*Set during construction to type(uint256).max / TOTAL_SUPPLY*


```solidity
uint256 public immutable MAX_BID_PRICE;
```


### CLAIM_BLOCK
The block at which purchased tokens can be claimed


```solidity
uint64 internal immutable CLAIM_BLOCK;
```


### VALIDATION_HOOK
An optional hook to be called before a bid is registered


```solidity
IValidationHook internal immutable VALIDATION_HOOK;
```


### $currencyRaisedQ96_X7
The total currency raised in the auction in Q96 representation, scaled up by X7


```solidity
ValueX7 internal $currencyRaisedQ96_X7;
```


### $sumCurrencyDemandAboveClearingQ96
The sum of currency demand in ticks above the clearing price

*This will increase every time a new bid is submitted, and decrease when bids are outbid.*


```solidity
uint256 internal $sumCurrencyDemandAboveClearingQ96;
```


### $_tokensReceived
Whether the TOTAL_SUPPLY of tokens has been received


```solidity
bool private $_tokensReceived;
```


## Functions
### constructor


```solidity
constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
    AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
    TokenCurrencyStorage(
        _token,
        _parameters.currency,
        _totalSupply,
        _parameters.tokensRecipient,
        _parameters.fundsRecipient,
        _parameters.requiredCurrencyRaised
    )
    TickStorage(_parameters.tickSpacing, _parameters.floorPrice)
    PermitSingleForwarder(IAllowanceTransfer(PERMIT2));
```

### onlyAfterAuctionIsOver

Modifier for functions which can only be called after the auction is over


```solidity
modifier onlyAfterAuctionIsOver();
```

### onlyAfterClaimBlock

Modifier for claim related functions which can only be called after the claim block


```solidity
modifier onlyAfterClaimBlock();
```

### onlyActiveAuction

Modifier for functions which can only be called after the auction is started and the tokens have been received


```solidity
modifier onlyActiveAuction();
```

### ensureCheckpointed

Modifier for functions which require the latest checkpoint to be up to date


```solidity
modifier ensureCheckpointed();
```

### onTokensReceived

Notify a distribution contract that it has received the tokens to distribute


```solidity
function onTokensReceived() external;
```

### isGraduated

Whether the auction has graduated as of the given checkpoint

*The auction is considered `graudated` if the clearing price is greater than the floor price
since that means it has sold all of the total supply of tokens.*


```solidity
function isGraduated() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the auction has graduated, false otherwise|


### _isGraduated

Whether the auction has graduated as of the given checkpoint

*The auction is considered `graudated` if the currency raised is greater than or equal to the required currency raised*


```solidity
function _isGraduated() internal view returns (bool);
```

### currencyRaised

Get the currency raised at the last checkpointed block

*This may be less than the balance of this contract if there are outstanding refunds for bidders*


```solidity
function currencyRaised() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The currency raised|


### _currencyRaised

Return the currency raised in uint256 representation


```solidity
function _currencyRaised() internal view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The currency raised|


### _sellTokensAtClearingPrice

Return a new checkpoint after advancing the current checkpoint by some `mps`
This function updates the cumulative values of the checkpoint, and
requires that the clearing price is up to date


```solidity
function _sellTokensAtClearingPrice(Checkpoint memory _checkpoint, uint24 deltaMps)
    internal
    returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint to sell tokens at its clearing price|
|`deltaMps`|`uint24`|The number of mps to sell|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The checkpoint with all cumulative values updated|


### _advanceToCurrentStep

Fast forward to the current step, selling tokens at the current clearing price according to the supply schedule

*The checkpoint MUST have the most up to date clearing price since `sellTokensAtClearingPrice` depends on it*


```solidity
function _advanceToCurrentStep(Checkpoint memory _checkpoint, uint64 blockNumber)
    internal
    returns (Checkpoint memory);
```

### _iterateOverTicksAndFindClearingPrice

Iterate to find the tick where the total demand at and above it is strictly less than the remaining supply in the auction

*If the loop reaches the highest tick in the book, `nextActiveTickPrice` will be set to MAX_TICK_PTR*


```solidity
function _iterateOverTicksAndFindClearingPrice(Checkpoint memory _checkpoint) internal returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The latest checkpoint|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The new clearing price|


### _unsafeCheckpoint

Internal function for checkpointing at a specific block number

*This updates the state of the auction accounting for the bids placed after the last checkpoint
Checkpoints are created at the top of each block with a new bid and does NOT include that bid
Because of this, we need to calculate what the new state of the Auction should be before updating
purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingQ96` value*


```solidity
function _unsafeCheckpoint(uint64 blockNumber) internal returns (Checkpoint memory _checkpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint64`|The block number to checkpoint at|


### _getFinalCheckpoint

Return the final checkpoint of the auction

*Only called when the auction is over. Changes the current state of the `step` to the final step in the auction
any future calls to `step.mps` will return the mps of the last step in the auction*


```solidity
function _getFinalCheckpoint() internal returns (Checkpoint memory);
```

### _submitBid


```solidity
function _submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
    internal
    returns (uint256 bidId);
```

### _processExit

Given a bid, tokens filled and refund, process the transfers and refund


```solidity
function _processExit(uint256 bidId, uint256 tokensFilled, uint256 currencySpentQ96) internal;
```

### checkpoint

Register a new checkpoint

*This function is called every time a new bid is submitted above the current clearing price*


```solidity
function checkpoint() public onlyActiveAuction returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|_checkpoint The checkpoint at the current block|


### submitBid

Submit a new bid

*Bids can be submitted anytime between the startBlock and the endBlock.*


```solidity
function submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData)
    public
    payable
    onlyActiveAuction
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`prevTickPrice`|`uint256`|The price of the previous tick|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|bidId The id of the bid|


### submitBid

Submit a new bid


```solidity
function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
    public
    payable
    onlyActiveAuction
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|bidId The id of the bid|


### exitBid

Exit a bid

*This function can only be used for bids where the max price is above the final clearing price after the auction has ended*


```solidity
function exitBid(uint256 bidId) external onlyAfterAuctionIsOver;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|


### exitPartiallyFilledBid

Exit a bid which has been partially filled

*This function can be used for fully filled or partially filled bids. For fully filled bids, `exitBid` is more efficient*


```solidity
function exitPartiallyFilledBid(uint256 bidId, uint64 lastFullyFilledCheckpointBlock, uint64 outbidBlock) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|
|`lastFullyFilledCheckpointBlock`|`uint64`||
|`outbidBlock`|`uint64`|The first checkpointed block where the clearing price is strictly > bid.maxPrice, or 0 if the bid is partially filled at the end of the auction|


### claimTokens

Claim tokens after the auction's claim block

*Anyone can claim tokens for any bid, the tokens are transferred to the bid owner*


```solidity
function claimTokens(uint256 _bidId) external onlyAfterClaimBlock ensureCheckpointed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`||


### claimTokensBatch

Claim tokens for multiple bids

*Anyone can claim tokens for bids of the same owner, the tokens are transferred to the owner*


```solidity
function claimTokensBatch(address _owner, uint256[] calldata _bidIds) external onlyAfterClaimBlock ensureCheckpointed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`||
|`_bidIds`|`uint256[]`||


### _internalClaimTokens

Internal function to claim tokens for a single bid


```solidity
function _internalClaimTokens(uint256 bidId) internal returns (address owner, uint256 tokensFilled);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner of the bid|
|`tokensFilled`|`uint256`|The amount of tokens filled|


### sweepCurrency

Withdraw all of the currency raised

*Can be called by anyone after the auction has ended*


```solidity
function sweepCurrency() external onlyAfterAuctionIsOver ensureCheckpointed;
```

### sweepUnsoldTokens

Sweep any leftover tokens to the tokens recipient

*This function can only be called after the auction has ended*


```solidity
function sweepUnsoldTokens() external onlyAfterAuctionIsOver ensureCheckpointed;
```

### claimBlock

The block at which the auction can be claimed


```solidity
function claimBlock() external view override(IAuction) returns (uint64);
```

### validationHook

The address of the validation hook for the auction


```solidity
function validationHook() external view override(IAuction) returns (IValidationHook);
```

### currencyRaisedQ96_X7

The currency raised as of the last checkpoint


```solidity
function currencyRaisedQ96_X7() external view override(IAuction) returns (ValueX7);
```

### sumCurrencyDemandAboveClearingQ96

The sum of demand in ticks above the clearing price


```solidity
function sumCurrencyDemandAboveClearingQ96() external view override(IAuction) returns (uint256);
```

