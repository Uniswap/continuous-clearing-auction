// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice A ValueX7 is a uint256 value that has been multiplied by MPS
/// @dev X7 values are used for demand values to avoid intermediate division by MPS
type ValueX7 is uint256;

using {saturatingSub, divUint256} for ValueX7 global;

/// @notice Subtract two ValueX7 values, returning zero on underflow.
/// @dev Wrapper around FixedPointMathLib.saturatingSub
function saturatingSub(ValueX7 a, ValueX7 b) pure returns (ValueX7) {
    return ValueX7.wrap(FixedPointMathLib.saturatingSub(ValueX7.unwrap(a), ValueX7.unwrap(b)));
}

/// @notice Divide a ValueX7 value by a uint256
function divUint256(ValueX7 a, uint256 b) pure returns (ValueX7) {
    return ValueX7.wrap(ValueX7.unwrap(a) / b);
}

/// @title ValueX7Lib
library ValueX7Lib {
    using ValueX7Lib for ValueX7;

    /// @notice The scaling factor for ValueX7 values (ConstantsLib.MPS)
    uint256 public constant X7 = ConstantsLib.MPS;

    /// @notice Multiply a uint256 value by MPS
    /// @dev This ensures that future operations will not lose precision
    /// @return The result as a ValueX7
    function scaleUpToX7(uint256 value) internal pure returns (ValueX7) {
        return ValueX7.wrap(value * X7);
    }

    /// @notice Divide a ValueX7 value by MPS
    /// @return The result as a uint256
    function scaleDownToUint256(ValueX7 value) internal pure returns (uint256) {
        return ValueX7.unwrap(value) / X7;
    }
}
