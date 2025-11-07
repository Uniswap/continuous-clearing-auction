// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @notice Library containing protocol constants
library ConstantsLib {
    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 constant MPS = 1e7;
    /// @notice The upper bound of a ValueX7 value
    uint256 constant X7_UPPER_BOUND = type(uint256).max / 1e7;

    /// @notice The maximum total supply of tokens that can be sold is 2^100 tokens, which is just above 1e30.
    /// @dev    We strongly believe that new tokens should have 18 decimals and a total supply less than one trillion.
    ///         This upper bound is chosen to prevent the Auction from being used with an extremely large token supply,
    ///         which would restrict the clearing price to be a very low price in the calculation below.
    uint128 constant MAX_TOTAL_SUPPLY = 1 << 100;

    /// @notice The maximum allowable price for a bid
    /// @dev This is lower than the maximum supported price in Uniswap v4 which is just under 2^224.
    ///      Since the entire amount of currency raised could be used for a liquidity position,
    ///      we must use a lower bound based on the max liquidity per tick defined in Uniswap v4,
    ///      given the smallest possible tick spacing of 1, the max liquidity per tick (L_max) is 2^107.
    ///      In Q96 form, this is 2^107 * 2^96 = 2^203.
    uint256 constant MAX_V4_LIQ_PER_TICK_X96 = 1 << 203;

    /// @notice The maximum allowable price for a bid
    /// @dev This is the maximum price that can be shifted left by 96 bits without overflowing a uint256
    uint256 constant MAX_V4_PRICE = (1 << 160) - 1;

    /// @notice The minimum allowable floor price is 2^32 + 1
    /// @dev This is the minimum price that fits in a uint160 after being inversed
    uint256 constant MIN_FLOOR_PRICE = (1 << 32) + 1;

    /// @notice The minimum allowable tick spacing
    /// @dev We don't allow tick spacing of 1 to avoid edge cases where the rounding of the clearing price
    ///      would cause the price to move between initialized ticks.
    uint256 constant MIN_TICK_SPACING = 2;
}
