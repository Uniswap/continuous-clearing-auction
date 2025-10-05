// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './ValueX7X7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Checkpoint {
    uint256 clearingPrice; // The X96 price which the auction is currently clearing at
    ValueX7X7 totalCurrencyRaisedX7X7; // The actual currency raised (sold for tokens) so far in the auction
    ValueX7X7 cumulativeCurrencyRaisedAtClearingPriceX7X7; // The tokens sold so far to this clearing price
    uint256 cumulativeMpsPerPrice; // A running sum of the ratio between mps and price
    uint24 cumulativeMps; // The number of mps sold in the auction so far (via the original supply schedule)
    uint64 prev; // Block number of the previous checkpoint
    uint64 next; // Block number of the next checkpoint
}

/// @title CheckpointLib
library CheckpointLib {
    using FixedPointMathLib for *;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using CheckpointLib for Checkpoint;

    /// @notice Get the remaining mps in the auction at the given checkpoint
    /// @param _checkpoint The checkpoint with `cumulativeMps` so far
    /// @return The remaining mps in the auction
    function remainingMpsInAuction(Checkpoint memory _checkpoint) internal pure returns (uint24) {
        return ConstantsLib.MPS - _checkpoint.cumulativeMps;
    }

    /// @notice Calculate the supply to price ratio. Will return zero if `price` is zero
    /// @dev This function returns a value in Q96 form
    /// @param mps The number of supply mps sold
    /// @param price The price they were sold at
    /// @return the ratio
    function getMpsPerPrice(uint24 mps, uint256 price) internal pure returns (uint256) {
        if (price == 0) return 0;
        // The bitshift cannot overflow because a uint24 shifted left 96 * 2 will always be less than 2^256
        return uint256(mps).fullMulDiv(FixedPoint96.Q96 ** 2, price);
    }

    /// @notice Return the total currency raised at the given checkpoint
    /// @param checkpoint the checkpoint
    /// @return The total currency raised in uint256 form
    function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint256) {
        return checkpoint.totalCurrencyRaisedX7X7.scaleDownToValueX7().scaleDownToUint256();
    }
}
