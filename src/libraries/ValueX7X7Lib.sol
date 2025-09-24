// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MPSLib} from './MPSLib.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A ValueX7X7 is a ValueX7 value that has been multiplied by MPS
/// @dev X7X7 values are used for supply values to avoid intermediate division by MPS
type ValueX7X7 is uint256;

using {add, sub, eq, mulUint256, divUint256, gte, fullMulDiv, fullMulDivUp} for ValueX7X7 global;

/// @notice Add two ValueX7 values
function add(ValueX7X7 a, ValueX7X7 b) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(ValueX7X7.unwrap(a) + ValueX7X7.unwrap(b));
}

/// @notice Subtract two ValueX7 values
function sub(ValueX7X7 a, ValueX7X7 b) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(ValueX7X7.unwrap(a) - ValueX7X7.unwrap(b));
}

/// @notice Check if a ValueX7X7 value is equal to another ValueX7X7 value
function eq(ValueX7X7 a, ValueX7X7 b) pure returns (bool) {
    return ValueX7X7.unwrap(a) == ValueX7X7.unwrap(b);
}

/// @notice Check if a ValueX7 value is greater than or equal to another ValueX7X7 value
function gte(ValueX7X7 a, ValueX7X7 b) pure returns (bool) {
    return ValueX7X7.unwrap(a) >= ValueX7X7.unwrap(b);
}

/// @notice Multiply a ValueX7 value by a uint256
function mulUint256(ValueX7X7 a, uint256 b) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(ValueX7X7.unwrap(a) * b);
}

/// @notice Divide a ValueX7 value by a uint256
function divUint256(ValueX7X7 a, uint256 b) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(ValueX7X7.unwrap(a) / b);
}

/// @notice Wrapper around FixedPointMathLib.fullMulDiv to support ValueX7 values
function fullMulDiv(ValueX7X7 a, ValueX7X7 b, ValueX7X7 c) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(FixedPointMathLib.fullMulDiv(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), ValueX7X7.unwrap(c)));
}

/// @notice Wrapper around FixedPointMathLib.fullMulDivUp to support ValueX7 values
function fullMulDivUp(ValueX7X7 a, ValueX7X7 b, ValueX7X7 c) pure returns (ValueX7X7) {
    return ValueX7X7.wrap(FixedPointMathLib.fullMulDivUp(ValueX7X7.unwrap(a), ValueX7X7.unwrap(b), ValueX7X7.unwrap(c)));
}

/// @title ValueX7X7Lib
library ValueX7X7Lib {
    using ValueX7Lib for ValueX7;
    using ValueX7X7Lib for ValueX7X7;

    /// @notice Multiply a uint256 value by MPS
    /// @dev This ensures that future operations (ex. scaleByMps) will not lose precision
    /// @return The result as a ValueX7
    function scaleUpToX7X7(ValueX7 value) internal pure returns (ValueX7X7) {
        return ValueX7X7.wrap(ValueX7.unwrap(value.mulUint256(MPSLib.MPS)));
    }

    /// @notice Divide a ValueX7 value by MPS
    /// @return The result as a uint256
    function scaleDownToValueX7(ValueX7X7 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(ValueX7X7.unwrap(value.divUint256(MPSLib.MPS)));
    }

    /// @notice Wrapper around free fullMulDiv function to support cases where we want to use uint256 values
    /// @dev Ensure that `b` and `c` should be compared against the ValueX7X7 value
    function fullMulDivUnchecked(ValueX7X7 a, uint256 b, uint256 c) internal pure returns (ValueX7X7) {
        return a.fullMulDiv(ValueX7X7.wrap(b), ValueX7X7.wrap(c));
    }
}
