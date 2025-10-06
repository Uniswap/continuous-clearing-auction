// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A ValueX7 is a uint256 value that has been multiplied by MPS
/// @dev X7 values are used for demand values to avoid intermediate division by MPS
type ValueX7 is uint256;

using {add, sub, eq, gte, mulUint256, divUint256, fullMulDiv, fullMulDivUp} for ValueX7 global;

/// @notice Add two ValueX7 values
function add(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) + ValueX7.unwrap(b));
}

/// @notice Subtract two ValueX7 values
function sub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) - ValueX7.unwrap(b));
}

/// @notice Check if a ValueX7 value is equal to another ValueX7 value
function eq(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) == ValueX7.unwrap(b);
}

/// @notice Check if a ValueX7 value is greater than or equal to another ValueX7 value
function gte(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) >= ValueX7.unwrap(b);
}

/// @notice Multiply a ValueX7 value by a uint256
function mulUint256(ValueX7 a, uint256 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) * b);
}

/// @notice Divide a ValueX7 value by a uint256
function divUint256(ValueX7 a, uint256 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) / b);
}

/// @notice Wrapper around FixedPointMathLib.fullMulDiv to support ValueX7 values
function fullMulDiv(ValueX7 a, ValueX7 b, ValueX7 c) pure returns (ValueX7) {
    return ValueX7.wrap(FixedPointMathLib.fullMulDiv(ValueX7.unwrap(a), ValueX7.unwrap(b), ValueX7.unwrap(c)));
}

/// @notice Wrapper around FixedPointMathLib.fullMulDivUp to support ValueX7 values
function fullMulDivUp(ValueX7 a, ValueX7 b, ValueX7 c) pure returns (ValueX7) {
    return ValueX7.wrap(FixedPointMathLib.fullMulDivUp(ValueX7.unwrap(a), ValueX7.unwrap(b), ValueX7.unwrap(c)));
}

/// @title ValueX7Lib
library ValueX7Lib {
    using ValueX7Lib for ValueX7;

    /// @notice The scaling factor for ValueX7 values (ConstantsLib.MPS)
    uint256 public constant X7 = ConstantsLib.MPS;

    /// @notice Multiply a uint256 value by MPS
    /// @dev This ensures that future operations (ex. scaleByMps) will not lose precision
    /// @return The result as a ValueX7
    function scaleUpToX7(uint256 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value * X7);
    }

    /// @notice Divide a ValueX7 value by MPS
    /// @return The result as a uint256
    function scaleDownToUint256(ValueX7 value) internal pure returns (uint256) {
        return ValueX7.unwrap(value.divUint256(X7));
    }

    /// @notice Wrapper around free fullMulDiv function to support cases where we want to use uint256 values
    /// @dev Ensure that `b` and `c` should be compared against the ValueX7 value
    function wrapAndFullMulDiv(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7) {
        return a.fullMulDiv(ValueX7.wrap(b), ValueX7.wrap(c));
    }

    /// @notice Wrapper around free fullMulDivUp function to support cases where we want to use uint256 values
    /// @dev Ensure that `b` and `c` should be compared against the ValueX7 value
    function wrapAndFullMulDivUp(ValueX7 a, uint256 b, uint256 c) internal pure returns (ValueX7) {
        return a.fullMulDivUp(ValueX7.wrap(b), ValueX7.wrap(c));
    }
}
