// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title DemandLib
/// @notice Library for helper functions related to demand resolution
library DemandLib {
    using ValueX7Lib for *;
    using FixedPointMathLib for uint256;

    /// @notice Resolve the demand at a given price, rounding up.
    ///         We only round up when we compare demand to supply so we never find a price that is too low.
    /// @dev "Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price
    /// @param currencyDemandX7 The demand to resolve
    /// @param price The price to resolve the demand at
    /// @return The resolved demand as a ValueX7
    function resolveRoundingUp(ValueX7 currencyDemandX7, uint256 price) internal pure returns (ValueX7) {
        return price == 0 ? ValueX7.wrap(0) : currencyDemandX7.wrapAndFullMulDivUp(FixedPoint96.Q96, price);
    }

    /// @notice Resolve the demand at a given price, rounding down
    ///         We always round demand down in all other cases (calculating supply sold to a price and bid withdrawals)
    /// @dev "Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price
    /// @param currencyDemandX7 The demand to resolve
    /// @param price The price to resolve the demand at
    /// @return The resolved demand as a ValueX7
    function resolveRoundingDown(ValueX7 currencyDemandX7, uint256 price) internal pure returns (ValueX7) {
        return price == 0 ? ValueX7.wrap(0) : currencyDemandX7.wrapAndFullMulDiv(FixedPoint96.Q96, price);
    }
}
