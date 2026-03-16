// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @notice Library containing protocol constants
library ConstantsLib {
    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 constant MPS = 1e7;
    /// @notice The upper bound of a ValueX7 value
    uint256 constant X7_UPPER_BOUND = type(uint256).max / 1e7;

    /// @notice The maximum total supply of tokens that can be sold in the Auction
    /// @dev    This is set to 2^100 tokens, which is just above 1e30, or one trillion units of a token with 18 decimals.
    ///         This upper bound is chosen to prevent the Auction from being used with an extremely large token supply,
    ///         which would restrict the clearing price to be a very low price in the calculation below.
    uint128 constant MAX_TOTAL_SUPPLY = 1 << 100;

    /// @notice The minimum allowable floor price is type(uint32).max + 1
    /// @dev This is the minimum price that fits in a uint160 after being inversed
    uint256 constant MIN_FLOOR_PRICE = uint256(type(uint32).max) + 1;

    /// @notice The minimum allowable tick spacing
    /// @dev We don't support tick spacings of 1 to avoid edge cases where the rounding of the clearing price
    ///      would cause the price to move between initialized ticks.
    uint256 constant MIN_TICK_SPACING = 2;
}
