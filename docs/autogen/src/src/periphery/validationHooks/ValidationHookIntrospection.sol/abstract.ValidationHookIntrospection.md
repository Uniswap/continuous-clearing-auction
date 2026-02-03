# ValidationHookIntrospection
[Git Source](https://github.com/Uniswap/twap-auction/blob/37817840a05eb60581df70139cc71f280836677f/src/periphery/validationHooks/ValidationHookIntrospection.sol)

**Inherits:**
[IValidationHookIntrospection](/src/periphery/validationHooks/ValidationHookIntrospection.sol/interface.IValidationHookIntrospection.md)

Base contract for validation hooks supporting basic introspection

Offchain interfaces and integrators should query `supportsInterface` to fuzz what types of validation are run by the hook


## Functions
### supportsInterface

Returns true if this contract implements the interface defined by
`interfaceId`. See the corresponding
https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
to learn more about how these ids are created.
This function call must use less than 30 000 gas.


```solidity
function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool);
```

