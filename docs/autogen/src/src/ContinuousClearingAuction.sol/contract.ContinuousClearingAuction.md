# ContinuousClearingAuction
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/ContinuousClearingAuction.sol)

**Inherits:**
[BidStorage](/src/BidStorage.sol/abstract.BidStorage.md), [CheckpointStorage](/src/CheckpointStorage.sol/abstract.CheckpointStorage.md), [StepStorage](/src/StepStorage.sol/abstract.StepStorage.md), [TickStorage](/src/TickStorage.sol/abstract.TickStorage.md), [TokenCurrencyStorage](/src/TokenCurrencyStorage.sol/abstract.TokenCurrencyStorage.md), BlockNumberish, ReentrancyGuardTransient, [IContinuousClearingAuction](/src/interfaces/IContinuousClearingAuction.sol/interface.IContinuousClearingAuction.md)

**Title:**
ContinuousClearingAuction

Implements a time weighted uniform clearing price auction

Can be constructed directly or through the ContinuousClearingAuctionFactory. In either case, users must validate
that the auction parameters are correct and not incorrectly set.

**Note:**
security-contact: security@uniswap.org


## State Variables
### MAX_BID_PRICE
The maximum price which a bid can be submitted at

Set during construction using MaxBidPriceLib.maxBidPrice() based on TOTAL_SUPPLY


```solidity
uint256 public immutable MAX_BID_PRICE
```


### CLAIM_BLOCK
The block at which purchased tokens can be claimed


```solidity
uint64 internal immutable CLAIM_BLOCK
```


### VALIDATION_HOOK
An optional hook to be called before a bid is registered


```solidity
IValidationHook internal immutable VALIDATION_HOOK
```


### $currencyRaisedQ96_X7
The total currency raised in the auction in Q96 representation, scaled up by X7


```solidity
ValueX7 internal $currencyRaisedQ96_X7
```


### $totalClearedQ96_X7
The total tokens sold in the auction so far, in Q96 representation, scaled up by X7


```solidity
ValueX7 internal $totalClearedQ96_X7
```


### $sumCurrencyDemandAboveClearingQ96
The sum of currency demand in ticks above the clearing price

This will increase every time a new bid is submitted, and decrease when bids are outbid.


```solidity
uint256 internal $sumCurrencyDemandAboveClearingQ96
```


### $clearingPrice
The most up to date clearing price, set on each call to `checkpoint`

This can be incremented manually by calling `forceIterateOverTicks`


```solidity
uint256 internal $clearingPrice
```


### $_tokensReceived
Whether the TOTAL_SUPPLY of tokens has been received


```solidity
bool private $_tokensReceived
```


## Functions
### constructor


```solidity
constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
    StepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
    TokenCurrencyStorage(
        _token,
        _parameters.currency,
        _totalSupply,
        _parameters.tokensRecipient,
        _parameters.fundsRecipient,
        _parameters.requiredCurrencyRaised
    )
    TickStorage(_parameters.tickSpacing, _parameters.floorPrice);
```

### onlyAfterAuctionIsOver

Modifier for functions which can only be called after the auction is over


```solidity
modifier onlyAfterAuctionIsOver() ;
```

### onlyAfterClaimBlock

Modifier for claim related functions which can only be called after the claim block


```solidity
modifier onlyAfterClaimBlock() ;
```

### onlyActiveAuction

Modifier for functions which can only be called after the auction is started and the tokens have been received


```solidity
modifier onlyActiveAuction() ;
```

### _onlyActiveAuction

Internal function to check if the auction is active

Submitting bids or checkpointing is not allowed unless the auction is active


```solidity
function _onlyActiveAuction() internal view;
```

### ensureEndBlockIsCheckpointed

Modifier for functions which require the latest checkpoint to be up to date


```solidity
modifier ensureEndBlockIsCheckpointed() ;
```

### onTokensReceived

Notify a distribution contract that it has received the tokens to distribute


```solidity
function onTokensReceived() external;
```

### lbpInitializationParams

Returns the LBP initialization parameters as determined by the implementing contract

The calling contract must be aware that the values returned in this function for `currencyRaised` and `tokensSold`
may not be reflective of the actual values if the auction did not graduate.


```solidity
function lbpInitializationParams() external view returns (LBPInitializationParams memory params);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`params`|`LBPInitializationParams`|The LBP initialization parameters|


### supportsInterface

Implements IERC165.supportsInterface to signal support for the ILBPInitializer interface


```solidity
function supportsInterface(bytes4 interfaceId) external pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|The interface identifier to check|


### clearingPrice

Get the most up to date clearing price

This will be at least as up to date as the latest checkpoint. It can be incremented from calls to `forceIterateOverTicks`


```solidity
function clearingPrice() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The current clearing price in Q96 form|


### isGraduated

Whether the auction has graduated as of the given checkpoint

The auction is considered graduated if the currency raised is greater than or equal to the required currency raised


```solidity
function isGraduated() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the auction has graduated, false otherwise|


### _isGraduated

Whether the auction has graduated as of the given checkpoint

The auction is considered `graudated` if the currency raised is greater than or equal to the required currency raised


```solidity
function _isGraduated() internal view returns (bool);
```

### currencyRaised

Get the currency raised at the last checkpointed block

This may be less than the balance of this contract if there are outstanding refunds for bidders


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
function _sellTokensAtClearingPrice(Checkpoint memory _checkpoint, uint24 _deltaMps)
    internal
    returns (Checkpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_checkpoint`|`Checkpoint`|The checkpoint to sell tokens at its clearing price|
|`_deltaMps`|`uint24`|The number of mps to sell|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|The checkpoint with all cumulative values updated|


### _advanceToStartOfCurrentStep

Fast forward to the start of the current step and return the number of `mps` sold since the last checkpoint


```solidity
function _advanceToStartOfCurrentStep(uint64 _blockNumber, uint64 _lastCheckpointedBlock)
    internal
    returns (AuctionStep memory step, uint24 deltaMps);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_blockNumber`|`uint64`|The current block number|
|`_lastCheckpointedBlock`|`uint64`|The block number of the last checkpointed block|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`step`|`AuctionStep`|The current step in the auction which contains `_blockNumber`|
|`deltaMps`|`uint24`|The number of `mps` sold between the last checkpointed block and the start of the current step|


### _iterateOverTicksAndFindClearingPrice

Iterate to find the tick where the total demand at and above it is strictly less than the remaining supply in the auction

If the loop reaches the highest tick in the book, `nextActiveTickPrice` will be set to MAX_TICK_PTR


```solidity
function _iterateOverTicksAndFindClearingPrice(uint256 _untilTickPrice) internal returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_untilTickPrice`|`uint256`|The tick price to iterate until|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The new clearing price|


### _checkpointAtBlock

Internal function for checkpointing at a specific block number

This updates the state of the auction accounting for the bids placed after the last checkpoint
Checkpoints are created at the top of each block with a new bid and does NOT include that bid
Because of this, we need to calculate what the new state of the Auction should be before updating
purely on the supply we will sell to the potentially updated `sumCurrencyDemandAboveClearingQ96` value


```solidity
function _checkpointAtBlock(uint64 _blockNumber) internal returns (Checkpoint memory _checkpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_blockNumber`|`uint64`|The block number to checkpoint at|


### _getFinalCheckpoint

Return the final checkpoint of the auction

Only called when the auction is over


```solidity
function _getFinalCheckpoint() internal returns (Checkpoint memory);
```

### _submitBid

Internal function for bid submission

Validates `maxPrice`, calls the validation hook (if set) and updates global state variables
For gas efficiency, `prevTickPrice` should be the price of the tick immediately before `maxPrice`.

Implementing functions must check that the actual value `amount` is received by the contract


```solidity
function _submitBid(
    uint256 _maxPrice,
    uint128 _amount,
    address _owner,
    uint256 _prevTickPrice,
    bytes calldata _hookData
) internal returns (uint256 bidId);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`bidId`|`uint256`|The id of the created bid|


### _processExit

Internal function for processing the exit of a bid

Given a bid, tokens filled and refund, process the transfers and refund
`exitedBlock` MUST be checked by the caller to prevent double spending


```solidity
function _processExit(uint256 _bidId, uint256 _tokensFilled, uint256 _currencySpentQ96) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`|The id of the bid to exit|
|`_tokensFilled`|`uint256`|The number of tokens filled|
|`_currencySpentQ96`|`uint256`|The amount of currency the bid spent|


### checkpoint

Register a new checkpoint

This function is called every time a new bid is submitted above the current clearing price


```solidity
function checkpoint() public onlyActiveAuction returns (Checkpoint memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Checkpoint`|_checkpoint The checkpoint at the current block|


### forceIterateOverTicks

Manually iterate over ticks to update the clearing price

This is used to prevent DoS attacks which initialize a large number of ticks


```solidity
function forceIterateOverTicks(uint256 _untilTickPrice) external onlyActiveAuction nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_untilTickPrice`|`uint256`|The tick price to iterate until|


### submitBid

Submit a new bid

Bids can be submitted anytime between the startBlock and the endBlock.


```solidity
function submitBid(
    uint256 _maxPrice,
    uint128 _amount,
    address _owner,
    uint256 _prevTickPrice,
    bytes calldata _hookData
) public payable onlyActiveAuction nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_maxPrice`|`uint256`||
|`_amount`|`uint128`||
|`_owner`|`address`||
|`_prevTickPrice`|`uint256`||
|`_hookData`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|bidId The id of the bid|


### submitBid

Submit a new bid without specifying the previous tick price

The call to `submitBid` checks `onlyActiveAuction` so it's not required on this function


```solidity
function submitBid(uint256 _maxPrice, uint128 _amount, address _owner, bytes calldata _hookData)
    external
    payable
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_maxPrice`|`uint256`||
|`_amount`|`uint128`||
|`_owner`|`address`||
|`_hookData`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|bidId The id of the bid|


### exitBid

Exit a bid

This function can only be used for bids where the max price is above the final clearing price after the auction has ended


```solidity
function exitBid(uint256 _bidId) external onlyAfterAuctionIsOver;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`||


### exitPartiallyFilledBid

Exit a bid which has been partially filled

This function can be used only for partially filled bids. For fully filled bids, `exitBid` must be used


```solidity
function exitPartiallyFilledBid(uint256 _bidId, uint64 _lastFullyFilledCheckpointBlock, uint64 _outbidBlock)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`||
|`_lastFullyFilledCheckpointBlock`|`uint64`||
|`_outbidBlock`|`uint64`||


### claimTokens

Claim tokens after the auction's claim block

Anyone can claim tokens for any bid, the tokens are transferred to the bid owner


```solidity
function claimTokens(uint256 _bidId) external onlyAfterClaimBlock ensureEndBlockIsCheckpointed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`||


### claimTokensBatch

Claim tokens for multiple bids

Anyone can claim tokens for bids of the same owner, the tokens are transferred to the owner


```solidity
function claimTokensBatch(address _owner, uint256[] calldata _bidIds)
    external
    onlyAfterClaimBlock
    ensureEndBlockIsCheckpointed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`||
|`_bidIds`|`uint256[]`||


### _internalClaimTokens

Internal function to claim tokens for a single bid


```solidity
function _internalClaimTokens(uint256 _bidId) internal returns (address owner, uint256 tokensFilled);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidId`|`uint256`|The id of the bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner of the bid|
|`tokensFilled`|`uint256`|The amount of tokens filled|


### sweepCurrency

Withdraw all of the currency raised

Can be called by anyone after the auction has ended


```solidity
function sweepCurrency() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed;
```

### sweepUnsoldTokens

Sweep any leftover tokens to the tokens recipient

This function can only be called after the auction has ended


```solidity
function sweepUnsoldTokens() external onlyAfterAuctionIsOver ensureEndBlockIsCheckpointed;
```

### currency

The currency being raised in the auction


```solidity
function currency() external view returns (address);
```

### token

The token being sold in the auction


```solidity
function token() external view returns (address);
```

### totalSupply

The total supply of tokens to sell


```solidity
function totalSupply() external view returns (uint128);
```

### tokensRecipient

The recipient of any unsold tokens at the end of the auction


```solidity
function tokensRecipient() external view returns (address);
```

### fundsRecipient

The recipient of the raised currency from the auction


```solidity
function fundsRecipient() external view returns (address);
```

### startBlock

The block at which the auction starts


```solidity
function startBlock() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The starting block number|


### endBlock

The block at which the auction ends


```solidity
function endBlock() external view returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The ending block number|


### claimBlock

The block at which the auction can be claimed


```solidity
function claimBlock() external view returns (uint64);
```

### validationHook

The address of the validation hook for the auction


```solidity
function validationHook() external view returns (IValidationHook);
```

### currencyRaisedQ96_X7

The currency raised as of the last checkpoint in Q96 representation, scaled up by X7

Most use cases will want to use `currencyRaised()` instead


```solidity
function currencyRaisedQ96_X7() external view returns (ValueX7);
```

### sumCurrencyDemandAboveClearingQ96

The sum of demand in ticks above the clearing price


```solidity
function sumCurrencyDemandAboveClearingQ96() external view returns (uint256);
```

### totalClearedQ96_X7

The total currency raised as of the last checkpoint in Q96 representation, scaled up by X7

Most use cases will want to use `totalCleared()` instead


```solidity
function totalClearedQ96_X7() external view returns (ValueX7);
```

### totalCleared

The total tokens cleared as of the last checkpoint in uint256 representation


```solidity
function totalCleared() public view returns (uint256);
```

