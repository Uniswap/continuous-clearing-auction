// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library PriceLib {
    /// @notice Returns true if price1 is strictly ordered before price2
    /// @dev Prices will be monotonically increasing or decreasing depending on the currency/token order
    ///      This function returns true if price1 would come before price2 in that order
    function priceStrictlyBefore(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool) {
        if (currencyIsToken0) {
            return price1 > price2;
        } else {
            return price1 < price2;
        }
    }

    /// @notice Returns true if price1 is ordered before or equal to price2
    /// @dev Prices will be monotonically increasing or decreasing depending on the currency/token order
    ///      This function returns true if price1 would come before or equal to price2 in that order
    function priceBeforeOrEqual(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool) {
        return priceStrictlyBefore(price1, price2, currencyIsToken0) || price1 == price2;
    }

    /// @notice Returns true if price1 is strictly ordered after price2
    /// @dev Prices will be monotonically increasing or decreasing depending on the currency/token order
    ///      This function returns true if price1 would come after price2 in that order
    function priceStrictlyAfter(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool) {
        if (currencyIsToken0) {
            return price1 < price2;
        } else {
            return price1 > price2;
        }
    }

    /// @notice Returns true if price1 is ordered after or equal to price2
    /// @dev Prices will be monotonically increasing or decreasing depending on the currency/token order
    ///      This function returns true if price1 would come after or equal to price2 in that order
    function priceAfterOrEqual(uint256 price1, uint256 price2, bool currencyIsToken0) internal pure returns (bool) {
        return priceStrictlyAfter(price1, price2, currencyIsToken0) || price1 == price2;
    }
}
