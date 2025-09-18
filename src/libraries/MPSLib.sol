// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A ValueX7 is a uint256 value that has been multiplied by MPS
type ValueX7 is uint256;

using {add, sub, eq, mulUint256, divUint256, gt, gte, fullMulDiv} for ValueX7 global;

/// @notice Add two ValueX7 values
function add(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) + ValueX7.unwrap(b));
}

/// @notice Subtract two ValueX7 values
function sub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) - ValueX7.unwrap(b));
}

/// @notice Check if a ValueX7 value is equal to its uint256 representation
function eq(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) == b;
}

/// @notice Check if a ValueX7 value is greater than its uint256 representation
function gt(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) > b;
}

/// @notice Check if a ValueX7 value is greater than or equal to its uint256 representation
function gte(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) >= b;
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

/// @title MPSLib
/// @notice Library for working with MPS related values
library MPSLib {
    using MPSLib for *;

    /// @notice we use milli-bips, or one thousandth of a basis point
    uint24 public constant MPS = 1e7;

    /// @notice Multiply a uint256 value by MPS
    /// @dev This ensures that future operations (ex. scaleByMps) will not lose precision
    /// @return The result as a ValueX7
    function scaleUpToX7(uint256 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value * MPS);
    }

    /// @notice Divide a ValueX7 value by MPS
    /// @return The result as a uint256
    function scaleDownToUint256(ValueX7 value) internal pure returns (uint256) {
        return ValueX7.unwrap(value) / MPS;
    }

    /// @notice Apply some `mps` to a ValueX7
    /// @dev Only operates on ValueX7 values to not lose precision from dividing by MPS
    /// @param value The ValueX7 value to apply `mps` to
    /// @param mps The number of mps to apply
    /// @return The result as a ValueX7
    function scaleByMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7) {
        return value.mulUint256(mps).divUint256(MPS);
    }
}
