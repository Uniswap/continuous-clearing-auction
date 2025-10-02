// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ConstantsLib
/// @notice Library containing protocol constants
library ConstantsLib {
    /// @notice The upper bound of a ValueX7X7 value
    uint256 constant X7X7_UPPER_BOUND = (type(uint256).max) / 1e14;
    /// @notice The upper bound of a ValueX7 value
    uint256 constant X7_UPPER_BOUND = (type(uint256).max) / 1e7;
}
