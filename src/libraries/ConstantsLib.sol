// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @notice Library containing protocol constants
library ConstantsLib {
    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 constant MPS = 1e7;
    /// @notice The upper bound of a ValueX7 value
    uint256 constant X7_UPPER_BOUND = (type(uint256).max) / 1e7;
    /// @notice The maximum total supply of tokens that can be sold is 1 quadrillion tokens assuming 18 decimals
    uint128 constant MAX_TOTAL_SUPPLY = 1e33;

    /// @notice The maximum allowable price for a bid
    /// @dev This is lower than the maximum supported price in Uniswap v4 which is just under 2^224.
    ///      Because the entire amount of currency raised could be used for a liquidity position,
    ///      we must use a lower bound based on the max liquidity per tick defined in Uniswap v4,
    ///      where given the smallest possible v4 tick spacing of 1, the max liquidity per tick is 2^122.
    ///      This is expressed in Q96 form as 2^122 * 2^96 = 2^218.
    uint256 constant MAX_BID_PRICE = 1 << 218;
}
