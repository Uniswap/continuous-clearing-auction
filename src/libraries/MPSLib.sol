// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A value scaled by MPS to prevent precision loss in calculations
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

/// @notice Check if ValueX7 equals uint256
function eq(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) == b;
}

/// @notice Check if ValueX7 is greater than uint256
function gt(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) > b;
}

/// @notice Check if ValueX7 is greater than or equal to uint256
function gte(ValueX7 a, uint256 b) pure returns (bool) {
    return ValueX7.unwrap(a) >= b;
}

/// @notice Multiply ValueX7 by uint256
function mulUint256(ValueX7 a, uint256 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) * b);
}

/// @notice Divide ValueX7 by uint256
function divUint256(ValueX7 a, uint256 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) / b);
}

/// @notice High-precision multiplication and division for ValueX7
function fullMulDiv(ValueX7 a, ValueX7 b, ValueX7 c) pure returns (ValueX7) {
    return ValueX7.wrap(FixedPointMathLib.fullMulDiv(ValueX7.unwrap(a), ValueX7.unwrap(b), ValueX7.unwrap(c)));
}

/// @title MPSLib
/// @notice Library for MPS calculations and ValueX7 operations
/// @dev MPS = milli-bips per second. 1 MPS = 0.0001% of total supply.
library MPSLib {
    using MPSLib for *;

    /// @notice Total MPS representing 100% of supply
    /// @dev All auction steps must sum to this value
    uint24 public constant MPS = 1e7;

    /// @notice Scale a uint256 value up by MPS
    /// @dev Prevents precision loss in fractional calculations
    /// @param value The value to scale
    /// @return The scaled ValueX7
    function scaleUpToX7(uint256 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value * MPS);
    }

    /// @notice Scale a ValueX7 value down by MPS
    /// @param value The ValueX7 to scale down
    /// @return The unscaled uint256
    function scaleDownToUint256(ValueX7 value) internal pure returns (uint256) {
        return ValueX7.unwrap(value) / MPS;
    }

    /// @notice Apply an MPS fraction to a ValueX7 value
    /// @dev Calculates (value * mps / MPS) for supply distribution
    /// @param value The ValueX7 value
    /// @param mps The MPS rate to apply
    /// @return The scaled result
    function scaleByMps(ValueX7 value, uint24 mps) internal pure returns (ValueX7) {
        return value.mulUint256(mps).divUint256(MPS);
    }
}
