# BaseERC1155ValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/periphery/validationHooks/BaseERC1155ValidationHook.sol)

**Inherits:**
[IBaseERC1155ValidationHook](/src/periphery/validationHooks/BaseERC1155ValidationHook.sol/interface.IBaseERC1155ValidationHook.md), [ValidationHookIntrospection](/src/periphery/validationHooks/ValidationHookIntrospection.sol/abstract.ValidationHookIntrospection.md)

Base validation hook for ERC1155 tokens

This hook validates that the sender is the owner of a specific ERC1155 tokenId
It is highly recommended to make the ERC1155 soulbound (non-transferable)


## State Variables
### erc1155
The ERC1155 token contract that is checked for ownership

Callers should query the returned interface's `balanceOf` method


```solidity
IERC1155 public immutable erc1155
```


### tokenId
The ERC1155 tokenId that is checked for ownership


```solidity
uint256 public immutable tokenId
```


## Functions
### constructor


```solidity
constructor(address _erc1155, uint256 _tokenId) ;
```

### validate

Require that the `owner` and `sender` of the bid hold at least one of the required ERC1155 token

MUST revert if the bid is invalid


```solidity
function validate(uint256, uint128, address owner, address sender, bytes calldata) public view virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`<none>`|`uint128`||
|`owner`|`address`|The owner of the bid|
|`sender`|`address`|The sender of the bid|
|`<none>`|`bytes`||


### supportsInterface

Extend the existing introspection support to signal that derived contracts inherit from BaseERC1155ValidationHook


```solidity
function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(ValidationHookIntrospection, IERC165)
    returns (bool);
```

## Events
### ERC1155TokenIdSet
Emitted when the ERC1155 tokenId is set


```solidity
event ERC1155TokenIdSet(address indexed tokenAddress, uint256 tokenId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenAddress`|`address`|The address of the ERC1155 token|
|`tokenId`|`uint256`|The ID of the ERC1155 token|

## Errors
### InvalidTokenAddress
Error thrown when the token address is invalid


```solidity
error InvalidTokenAddress();
```

### NotOwnerOfERC1155Token
Error thrown when the sender is not the owner of the ERC1155 tokenId


```solidity
error NotOwnerOfERC1155Token(uint256 tokenId);
```

### SenderMustBeOwner
Error thrown when the sender is not the owner of the ERC1155 token


```solidity
error SenderMustBeOwner();
```

