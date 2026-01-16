# GatedERC1155ValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/949d1892c9cdad238344a57f13bea4cf1aa50924/src/periphery/validationHooks/GatedERC1155ValidationHook.sol)

**Inherits:**
[BaseERC1155ValidationHook](/src/periphery/validationHooks/BaseERC1155ValidationHook.sol/contract.BaseERC1155ValidationHook.md), BlockNumberish

Validation hook for ERC1155 tokens that requires the sender to hold a specific token until a certain block number

It is highly recommended to make the ERC1155 soulbound (non-transferable)


## State Variables
### gateUntil
The block number until which the validation check is enforced


```solidity
uint256 public immutable gateUntil
```


## Functions
### constructor


```solidity
constructor(address _erc1155, uint256 _tokenId, uint256 _gateUntil) BaseERC1155ValidationHook(_erc1155, _tokenId);
```

### validate

Require that the `owner` and `sender` of the bid hold at least one of the required ERC1155 token

This check is enforced until the `gateUntil` block number


```solidity
function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
    public
    view
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxPrice`|`uint256`|The maximum price the bidder is willing to pay|
|`amount`|`uint128`|The amount of the bid|
|`owner`|`address`|The owner of the bid|
|`sender`|`address`|The sender of the bid|
|`hookData`|`bytes`|Additional data to pass to the hook required for validation|


