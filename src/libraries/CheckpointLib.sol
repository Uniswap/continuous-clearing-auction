// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {BidLib} from './BidLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {MPSLib, ValueX7} from './MPSLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Checkpoint structure representing auction state at a specific block
/// @dev Contains all data needed for bid fill calculations and auction progression tracking
struct Checkpoint {
    /// @notice Current clearing price (Q96 fixed-point format)
    uint256 clearingPrice;
    /// @notice Total tokens sold/cleared so far (ValueX7 format)
    ValueX7 totalCleared;
    /// @notice Demand above clearing price, resolved to token units (ValueX7 format)
    ValueX7 resolvedDemandAboveClearingPrice;
    /// @notice Cumulative MPS/price ratio for weighted average calculations
    uint256 cumulativeMpsPerPrice;
    /// @notice Cumulative supply sold exactly at clearing price (for partial fills)
    ValueX7 cumulativeSupplySoldToClearingPriceX7;
    /// @notice Total MPS processed up to this checkpoint
    uint24 cumulativeMps;
    /// @notice MPS rate during this checkpoint period
    uint24 mps;
    /// @notice Previous checkpoint block number (linked list traversal)
    uint64 prev;
    /// @notice Next checkpoint block number (linked list traversal)
    uint64 next;
}

/// @title CheckpointLib
/// @notice Library for checkpoint operations and bid fill calculations
/// @dev Provides functions for supply calculation, price-weighted metrics, and currency
///      raised calculations. Uses ValueX7 scaling throughout to maintain precision.
library CheckpointLib {
    using FixedPointMathLib for *;
    using AuctionStepLib for uint256;
    using MPSLib for *;
    using CheckpointLib for Checkpoint;

    /// @notice Calculates available supply for the current period with rollover handling
    /// @dev Implements proportional supply allocation: remaining_supply * (mps / remaining_mps).
    ///      This ensures unsold supply from previous periods rolls over to current periods,
    ///      maintaining the total supply constraint while allowing flexible distribution.
    /// @param checkpoint Current checkpoint state with totalCleared and cumulativeMps
    /// @param totalSupplyX7 Total auction supply (ValueX7 format, immutable)
    /// @param mps MPS rate for the current period
    function getSupply(Checkpoint memory checkpoint, ValueX7 totalSupplyX7, uint24 mps)
        internal
        pure
        returns (ValueX7)
    {
        uint24 mpsRemainingInAuction = MPSLib.MPS - checkpoint.cumulativeMps;
        return totalSupplyX7.sub(checkpoint.totalCleared).mulUint256(mps).divUint256(mpsRemainingInAuction);
    }

    /// @notice Calculates MPS-weighted price contribution for average price tracking
    /// @dev Returns (mps * Q96^2) / price in Q96 format. Used to build cumulative
    ///      weighted averages for currency raised calculations. Returns 0 if price is 0.
    /// @param mps Amount of supply MPS sold at this price
    /// @param price The clearing price (Q96 format)
    /// @return Price-weighted MPS contribution in Q96 format
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
