// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A ValueX7 is a uint256 value that has been multiplied by 1e7 (ConstantsLib.MPS)
/// @dev X7 values are used for demand and supply values to defer division
type ValueX7 is uint256;

using {add as +, sub as -, gte as >=, min} for ValueX7 global;

/// @notice Add two ValueX7 values and return the result as a ValueX7
function add(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) + ValueX7.unwrap(b));
}

/// @notice Subtract two ValueX7 values and return the result as a ValueX7
function sub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) - ValueX7.unwrap(b));
}

/// @notice Return true if a is greater than or equal to b
function gte(ValueX7 a, ValueX7 b) pure returns (bool) {
    return ValueX7.unwrap(a) >= ValueX7.unwrap(b);
}

/// @notice Return the minimum of two ValueX7 values
/// @dev Branchless ternary evaluation for `a < b ? a : b`
function min(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    uint256 a_ = ValueX7.unwrap(a);
    uint256 b_ = ValueX7.unwrap(b);
    uint256 c_;
    /// @solidity memory-safe-assembly
    assembly {
        c_ := xor(a_, mul(xor(a_, b_), lt(b_, a_)))
    }
    return ValueX7.wrap(c_);
}
