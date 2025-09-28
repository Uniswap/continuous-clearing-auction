// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Checkpoint {
    uint256 clearingPrice;
    uint128 totalCleared;
    uint128 resolvedDemandAboveClearingPrice;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
    uint256 cumulativeMpsPerPrice;
    uint256 cumulativeSupplySoldToClearingPrice;
}

/// @title CheckpointLib
library CheckpointLib {
    using FixedPointMathLib for *;
    using AuctionStepLib for uint128;
    using CheckpointLib for Checkpoint;

    /// @notice Calculate the actual supply to sell given the total cleared in the auction so far
    /// @param checkpoint The last checkpointed state of the auction
    /// @param totalSupply immutable total supply of the auction
    /// @param mps the number of mps, following the auction sale schedule
    function getSupply(Checkpoint memory checkpoint, uint128 totalSupply, uint24 mps) internal pure returns (uint128) {
        return uint128(
            (totalSupply - checkpoint.totalCleared).fullMulDiv(mps, AuctionStepLib.MPS - checkpoint.cumulativeMps)
        );
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

    /// @notice Calculate the total currency raised
    /// @param checkpoint The checkpoint to calculate the currency raised from
    /// @return The total currency raised
    function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint128) {
        return uint128(
            checkpoint.totalCleared.fullMulDiv(
                checkpoint.cumulativeMps * FixedPoint96.Q96, checkpoint.cumulativeMpsPerPrice
            )
        );
    }
}
