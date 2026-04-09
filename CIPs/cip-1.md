---
title: Validation hook interface standard
description: An interface standard for validation hooks used in the Continuous Clearing Auction (CCA) protocol.
author: Eric Zhong (@zhongeric)
discussions-to: https://github.com/Uniswap/continuous-clearing-auction/discussions/319
status: Draft
type: Standards Track
category: CCA
created: 2026-02-04
requires: ERC165
---

## Abstract

Validation hooks are powerful extensions to CCA auctions that allow for custom validation logic to be applied to bids. This standard defines the interface for validation hooks to improve interoperability and composability.

## Motivation

While there is a standard interface for validation hooks, it is underspecfied in terms of the shape of the `hookData` parameter, and does not support ERC165 introspection which makes it difficult for offchain interfaces to trustlessly interact with them.

## Specification
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Validation hooks MUST implement the `IValidationHook` interface as defined in [IValidationHook.sol](../src/interfaces/IValidationHook.sol).

```solidity
interface IValidationHook {
    /// @notice Validate a bid
    /// @dev MUST revert if the bid is invalid
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param sender The sender of the bid
    /// @param hookData Additional data to pass to the hook required for validation
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData) external;
}
```

Implementing contracts MUST revert to prevent a bid from being submitted into the auction.

Hooks MUST also implement the `IERC165` interface as defined in [IERC165.sol](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-165.md).

```solidity
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

For simplicity, hooks MAY inherit the OPTIONAL contract [ValidationHookIntrospection](../src/periphery/validationHooks/ValidationHookIntrospection.sol). This provides out of the box support for callers to query support for the `IERC165` and `IValidationHook` interfaces.

## Rationale

ERC165 is a widely adopted standard for discovering the interfaces implemented by a contract. This standard defines the `IValidationHook` interface for validation hooks, and the `IERC165` interface for introspection.

## Backwards Compatibility

No backward compatibility issues found.

## Reference Implementation

See:
- [IValidationHook.sol](../src/interfaces/IValidationHook.sol)
- [ValidationHookIntrospection.sol](../src/periphery/validationHooks/ValidationHookIntrospection.sol)

## Security Considerations

Inherits the security considerations of the [ERC165](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-165.md) standard.

## Copyright

Copyright and related rights waived via [MIT](../LICENSE.md).