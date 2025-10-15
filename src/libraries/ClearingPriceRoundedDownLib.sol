// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ClearingPriceRoundedDownLib
/// @notice Library for storing the rounded down clearing price transiently
/// @dev The only reason to transient storage over memory is because this is not called frequently
/// TODO: this library can be removed once the transient keyword is supported in solidity
library ClearingPriceRoundedDownLib {
    /// @notice The slot holding the protocol carry: bytes32(uint256(keccak256("ClearingPriceRoundedDownLib")) - 1)
    bytes32 internal constant CLEARING_PRICE_ROUNDED_DOWN_LIB_SLOT =
        0xd30d9d016cea51b92d32e1feb325eebcbc560bff2558b313e5da5b7e4021dc4f;

    function get() internal view returns (uint256 price) {
        assembly ("memory-safe") {
            price := tload(CLEARING_PRICE_ROUNDED_DOWN_LIB_SLOT)
        }
    }

    function set(uint256 price) internal {
        assembly ("memory-safe") {
            tstore(CLEARING_PRICE_ROUNDED_DOWN_LIB_SLOT, price)
        }
    }
}
