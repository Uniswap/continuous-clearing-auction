# IBaseERC1155ValidationHook
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/periphery/validationHooks/BaseERC1155ValidationHook.sol)

**Inherits:**
[IValidationHookIntrospection](/src/periphery/validationHooks/ValidationHookIntrospection.sol/interface.IValidationHookIntrospection.md)


## Functions
### erc1155

The ERC1155 token contract that is checked for ownership

Callers should query the returned interface's `balanceOf` method


```solidity
function erc1155() external view returns (IERC1155);
```

### tokenId

The ERC1155 tokenId that is checked for ownership


```solidity
function tokenId() external view returns (uint256);
```

