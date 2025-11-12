// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title MaxBidPriceLib
/// @notice Library for calculating the maximum bid price for a given total supply
/// @dev The two are generally inversely correlated with certain constraints.
library MaxBidPriceLib {
    /**
     * @dev Given a total supply we want to find the maximum bid price such that both the
     * token liquidity and currency liquidity at the end of the Auction are less than the
     * maximum liquidity supported by Uniswap v4.
     *
     * The chart below shows the shaded area of valid (max bid price, total supply) value pairs such that
     * both calculated liquidity values are less than the maximum liquidity supported by Uniswap v4.
     * (x axis represents the max bid price in log form, and y is the total supply in log form)
     *
     * y ↑
     * |               :                         :   :
     * |                                            :                                  :
     * 128 +               :                               :
     * |                                                  :                            :
     * |               :                                 :   :
     * |                                                    :                          :
     * |               :                                       :
     * |                                                          :                    :
     * |               :                                         :   : (x=110, y=100)
     * | : : : : : : : +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+ : ::: : : : : : : : : : : : : : : : : : : : : : : : : : : : : : : : :
     * 96 +            +############################################   :
     * |               #################################################  :            :
     * |               +#################################################+#  :
     * |               #####################################################+          :
     * |               +#######################################################:
     * |               ########################################################## :    :
     * |               +#########################################################+#  :
     * |               #############################################################+  :
     * 64 +            +###############################################################: (x=160, y=62)
     * |               ################################################################:  :
     * |               +###############################################################  :   :
     * |               ################################################################:    :
     * |               +###############################################################        :
     * |               ################################################################:          :
     * |               +###############################################################          :   :
     * |               ################################################################:            :
     * 32 +            +###############################################################                :
     * |               ################################################################:                  :
     * |               +###############################################################                  :   :
     * |               ################################################################:                    :
     * |               +###############################################################                        :
     * |               ################################################################:                          :
     * |               +###############################################################+               +         :   : +
     * +---------------+###############+###############+###############+###############+---------------+---------------+--------------- x (max price)
     *  0              32              64              96              128             160             192             224           256
     *
     *
     * Legend:
     * x = max bid price in log form
     * y = total supply in log form
     * L_max = 2^107 (the lowest max liquidity per tick supported in Uniswap v4)
     * p_sqrtMax = 1461446703485210103287273052203988822378723970342 (max sqrt price in Uniswap v4)
     * p_sqrtMin = 4295128739 (min sqrt price in Uniswap v4)
     * x < 160, x > 32; (minimum price of 2^32, maximum price of 2^160)
     * y < 100; (minimum supply of 2^0 or 1, maximum supply of 2^100)
     *
     * Equations for liquidity amounts in Uniswap v4:
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
    ///      This is the intersection of `maxPriceKeepingCurrencyRaisedUnderInt128Max` and MAX_V4_PRICE,
    ///      meaning that because we can't support prices above uint160.max, all total supply values at or below
    ///      this threshold are capped at MAX_V4_PRICE.
    uint256 constant LOWER_TOTAL_SUPPLY_THRESHOLD = 1 << 62;

    /// @notice Calculates the maximum bid price for a given total supply
    /// @dev Total supply values under the LOWER_TOTAL_SUPPLY_THRESHOLD are capped at MAX_V4_PRICE
    function maxBidPrice(uint128 _totalSupply) internal pure returns (uint256) {
        // Small total supply values would return a price which exceeds the max v4 price, so we cap it at MAX_V4_PRICE
        if (_totalSupply <= LOWER_TOTAL_SUPPLY_THRESHOLD) return MAX_V4_PRICE;
        /**
         * Derivation: For a given total supply y (in log space), find the max bid price x (in log space)
         * The equations in the chart are equivalent for both currency/token sort orders (intuitive given a full range position).
         * Token1 liquidity is the limiting factor, so we use L_1 for simplicity:
         *  2^(x+y) / |2^((x+96)/2)-p_sqrtMin| < L_max
         *  2^(x+y) < L_max * |2^((x+96)/2)-p_sqrtMin|
         * We substitute a larger number than p_sqrtMin such that |2^((x+96)/2)-p_sqrtMin| ~ 2^((x+96)/2 - 1)
         *  2^(x+y) < L_max * 2^((x+96)/2 - 1)
         * Using 2^107 for L_max, we get:
         *  2^(x+y) < 2^107 * 2^((x+96)/2 - 1)
         * Taking the log2 of both sides, we get:
         *  x + y < 107 + (x+96) / 2 - 1
         *  x + y < 107 + x/2 + 48 - 1
         * Since we are given total supply (y), we can solve for x:
         *  x/2 = 107 + 47 - y
         *  x/2 = 154 - y
         *  x = 2 * (154 - y)
         * We want to find 2^x, not `x` so we take both sides to the power of 2:
         *  2^x = (2^154 / y) ** 2
         *
         * Because we return early if total supply is less than 2^62 the result of this will not overflow a uint256.
         */
        uint256 maxPriceKeepingLiquidityUnderMax = uint256((1 << 154) / _totalSupply) ** 2;

        // Additionally, we need to ensure that the currency raised is <= int128.max (2^127 - 1)
        // since PoolManager will cast it to int128 when the position is created.
        // The maxmimum currencyRaised in the auction is equal to totalSupply * maxBidPrice / Q96
        // To be conservative, we ensure that it is under 2^126, and rearranging the equation we get:
        // maxBidPrice < (2^126 * Q96) / totalSupply = 2^222 / totalSupply
        uint256 maxPriceKeepingCurrencyRaisedUnderInt128Max = uint256(1 << 222) / _totalSupply;

        // Take the minimum of the two to ensure that the (max bid price, total supply) pair is within the valid range.
        return FixedPointMathLib.min(maxPriceKeepingLiquidityUnderMax, maxPriceKeepingCurrencyRaisedUnderInt128Max);
    }
}
