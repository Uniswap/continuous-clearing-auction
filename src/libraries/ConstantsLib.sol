// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @notice Library containing protocol constants
library ConstantsLib {
    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 constant MPS = 1e7;
    /// @notice The upper bound of a ValueX7 value
    uint256 constant X7_UPPER_BOUND = type(uint256).max / 1e7;
    /// @notice The maximum total supply of tokens that can be sold is 1 trillion tokens assuming 18 decimals
    uint128 constant MAX_TOTAL_SUPPLY = 1e30;

    /// @notice The maximum allowable price for a bid
    /// @dev This is lower than the maximum supported price in Uniswap v4 which is just under 2^224.
    ///      Since the entire amount of currency raised could be used for a liquidity position,
    ///      we must use a lower bound based on the max liquidity per tick defined in Uniswap v4,
    ///      given the smallest possible tick spacing of 1, the max liquidity per tick (L_max) is 2^107.
    ///
    ///      Given that L_max = min(L_0, L_1), where L_0 is the amount0 liquidity and L_1 is the amount1 liquidity,
    ///      we can express L in terms of amount0 and amount1, as well as some price bound `k`: [2^-k, 2^k]
    ///         amount0 <= L_max * (sqrt(P_max) - sqrt(k)) / (sqrt(P_max) * sqrt(k))
    ///                 <= L_max * (P_max^(-1/2) - k^(-1/2))
    ///                 <= L_max * (k^(-1/2)) , given that P_max is extremely large and to the power of -1/2 is ~0
    ///                 <= 2^(107 - k/2)
    ///      and similarly,
    ///         amount1 <= L_max * (k^(-1/2))
    ///                 <= 2^(107 - k/2)
    ///      Since `k` is minimized when amount0 or amount 1 are largest, so substitute the MAX_TOTAL_SUPPLY for amount to find `k`
    ///                 <= 2^107 / 2^(k/2)
    ///        2^(k/2)  <= 2^107 / 2^100
    ///        k/2 <= 7
    ///        k <= 14
    ///      Therefore, our price range is [2^-14 to 2^14].
    ///
    ///      Since price is in Q96 form we need to multiply 2^107 by 2^96 before dividing by the total supply.
    ///      If total supply is 1, the max price will be 2^203. The price will be 2^14 * 2^96 = 2^110 when total supply == MAX_TOTAL_SUPPLY.
    ///      Integrators and users should be aware that in the case where the currency is less valuable
    ///      than the token and the total supply is very large, the clearing price will be capped at a low price.
    uint256 constant MAX_BID_PRICE = 1 << 203;
}
