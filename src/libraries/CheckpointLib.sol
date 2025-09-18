// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {BidLib} from './BidLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {MPSLib, ValueX7} from './MPSLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Checkpoint {
    uint256 clearingPrice;
    ValueX7 totalCleared;
    ValueX7 resolvedDemandAboveClearingPrice;
    uint256 cumulativeMpsPerPrice;
    ValueX7 cumulativeSupplySoldToClearingPriceX7;
    uint24 cumulativeMps;
    uint24 mps;
    uint64 prev;
    uint64 next;
}

/// @title CheckpointLib
library CheckpointLib {
    using FixedPointMathLib for *;
    using AuctionStepLib for uint256;
    using MPSLib for *;
    using CheckpointLib for Checkpoint;

    /// @notice Calculate the actual supply to sell given the total cleared in the auction so far
    /// @param checkpoint The last checkpointed state of the auction
    /// @param totalSupplyX7 immutable total supply of the auction
    /// @param mps the number of mps, following the auction sale schedule
    function getSupply(Checkpoint memory checkpoint, ValueX7 totalSupplyX7, uint24 mps)
        internal
        pure
        returns (ValueX7)
    {
        uint24 mpsRemainingInAuction = MPSLib.MPS - checkpoint.cumulativeMps;
        return totalSupplyX7.sub(checkpoint.totalCleared).mulUint256(mps).divUint256(mpsRemainingInAuction);
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
    function getCurrencyRaised(Checkpoint memory checkpoint) internal pure returns (uint256) {
        return checkpoint.totalCleared.fullMulDiv(
            ValueX7.wrap(checkpoint.cumulativeMps * FixedPoint96.Q96), ValueX7.wrap(checkpoint.cumulativeMpsPerPrice)
        ).scaleDownToUint256();
    }
}
