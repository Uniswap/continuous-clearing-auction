// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A ValueX7 is a uint256 value that has been multiplied by 1e7 (ConstantsLib.MPS)
/// @dev X7 values are used for demand and supply values to defer division
type ValueX7 is uint256;

using {add, saturatingSub} for ValueX7 global;

/// @notice Add two ValueX7 values and return the result as a ValueX7
function add(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) + ValueX7.unwrap(b));
}

/// @notice Subtract two ValueX7 values, returning zero on underflow.
/// @dev Wrapper around FixedPointMathLib.saturatingSub
function saturatingSub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(FixedPointMathLib.saturatingSub(ValueX7.unwrap(a), ValueX7.unwrap(b)));
}
