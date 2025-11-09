// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title MaxBidPriceLib
/// @notice Library for calculating the maximum bid price for a given total supply
/// @dev The two are generally inversely correlated with certain constraints.
library MaxBidPriceLib {
    /**
     * The chart below shows the shaded area of valid (max bid price, total supply) value pairs such that
     * both calculated liquidity values are less than the maximum liquidity supported by Uniswap v4.
     * (x axis represents the max bid price in log form, and y is the total supply in log form)
     *
     *     y (total supply) ↑
     * 128 +
     *     |
     *     |
     *     |
     *     |
     *     |
     *     |
     *     |               ######################################### (110, 100)
     *  96 +               #############################################
     *     |               #################################################
     *     |               #####################################################
     *     |               #########################################################
     *     |               #############################################################
     *     |               ################################################################ (160, 75)
     *     |               ################################################################
     *     |               ################################################################
     *  64 +               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *  32 +               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *     |               ################################################################
     *   0 +---------------+###############+###############+###############+###############+---------------+---------------+---------------> x (max bid price)
     *                    32              64              96              128             160             192             224             256
     *
     * Legend:
     * L_max = 2^107
     * p_sqrtMax = 1461446703485210103287273052203988822378723970342
     * p_sqrtMin = 4295128739
     * x < 160, x > 32; y < 100
     * Equations:
     * 1) If currencyIsCurrency1, L_0 = (2^y * ((2^((x+96)/2) * 2^160) / 2^96)) / |2^((x+96)/2)-p_sqrtMax| < L_max
     * 2)                         L_1 = (2^(x+y)) / |2^((x+96)/2)-p_sqrtMin| < L_max
     * 3) if currencyIsCurrency0, L_0 = (2^y * p_sqrtMax * 2^((192-x+96)/2)) / (2^(192-x+96) * |p_sqrtMax-2^((192-x+96)/2)|) < L_max
     * 4)                         L_1 = (2^(y+96)) / |2^((192-x+96)/2)-p_sqrtMin| < L_max
     */
    /// @notice The maximum allowable price for a bid is type(uint160).max
    /// @dev This is the maximum price that can be shifted left by 96 bits without overflowing a uint256
    uint256 constant MAX_V4_PRICE = type(uint160).max;

    /// @notice The total supply value below which the maximum bid price is capped at MAX_V4_PRICE
    /// @dev Since the two are inversely correlated, generally lower total supply = higher max bid price
    ///      However, for very small total supply values we still can't exceed the max v4 price.
    uint256 constant LOWER_TOTAL_SUPPLY_THRESHOLD = 1 << 75;

    /// @notice Calculates the maximum bid price for a given total supply
    /// @dev Total supply values under the LOWER_TOTAL_SUPPLY_THRESHOLD are capped at MAX_V4_PRICE
    function maxBidPrice(uint128 _totalSupply) internal pure returns (uint256) {
        if (_totalSupply < LOWER_TOTAL_SUPPLY_THRESHOLD) return MAX_V4_PRICE;
        return uint256((1 << 155) / _totalSupply) ** 2;
    }
}
