// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

library MaxBidPriceLib {
    // TODO: comment
    uint256 constant NUMERATOR = 1 << 155;

    // TODO: comment
    // all total supply under 1<<75 are capped at MAX_V4_PRICE
    uint256 constant MIN_SUPPLY_THRESHOLD = 1 << 75;

    /// @notice The maximum allowable price for a bid is type(uint160).max
    /// @dev This is the maximum price that can be shifted left by 96 bits without overflowing a uint256
    uint256 constant MAX_V4_PRICE = type(uint160).max;

    /// @notice Requires totalSupply to be greater than 1 << 27
    function maxBidPrice(uint128 _totalSupply) internal pure returns (uint256) {
        if (_totalSupply < MIN_SUPPLY_THRESHOLD) return MAX_V4_PRICE;
        return uint256(NUMERATOR / _totalSupply) ** 2;
    }
}
