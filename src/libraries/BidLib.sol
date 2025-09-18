// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {Demand, DemandLib} from './DemandLib.sol';

import {FixedPoint96} from './FixedPoint96.sol';
import {MPSLib, ValueX7} from './MPSLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint64 exitedBlock; // Block number when the bid was exited
    uint256 maxPrice; // The max price of the bid
    address owner; // Who is allowed to exit the bid
    uint256 amount; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

/// @title BidLib
library BidLib {
    using AuctionStepLib for uint256;
    using DemandLib for ValueX7;
    using MPSLib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    uint256 public constant PRECISION = 1e18;

    /// @notice Calculate the effective amount of a bid based on the mps denominator
    /// @param amount The amount of the bid
    /// @param mpsDenominator The portion of the auction (in mps) which the bid was spread over
    /// @return The effective amount of the bid
    function effectiveAmount(uint256 amount, uint24 mpsDenominator) internal pure returns (ValueX7) {
        return amount.scaleUpToX7().mulUint256(MPSLib.MPS).divUint256(mpsDenominator);
    }

    /// @notice Convert a bid to a demand
    function toDemand(Bid memory bid, uint24 mpsDenominator) internal pure returns (Demand memory demand) {
        ValueX7 bidDemandOverRemainingAuctionX7 = bid.amount.effectiveAmount(mpsDenominator);
        if (bid.exactIn) {
            demand.currencyDemandX7 = bidDemandOverRemainingAuctionX7;
        } else {
            demand.tokenDemandX7 = bidDemandOverRemainingAuctionX7;
        }
    }

    /// @notice Calculate the input amount required for an amount and maxPrice
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param maxPrice The max price of the bid
    /// @return The input amount required for an amount and maxPrice
    function inputAmount(bool exactIn, uint256 amount, uint256 maxPrice) internal pure returns (uint256) {
        return exactIn ? amount : amount.fullMulDivUp(maxPrice, FixedPoint96.Q96);
    }

    /// @notice Calculate the input amount required to place the bid
    /// @param bid The bid
    /// @return The input amount required to place the bid
    function inputAmount(Bid memory bid) internal pure returns (uint256) {
        return inputAmount(bid.exactIn, bid.amount, bid.maxPrice);
    }
}
