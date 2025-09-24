// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {Demand, DemandLib} from './DemandLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {MPSLib} from './MPSLib.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './ValueX7X7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint24 startCumulativeMps; // Cumulative mps at the start of the bid
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
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    /// @notice Calculate the number of mps remaining in the auction since the bid was submitted
    /// @param bid The bid to calculate the remaining mps for
    /// @return The number of mps remaining in the auction
    function mpsRemainingInAuction(Bid memory bid) internal pure returns (uint24) {
        return MPSLib.MPS - bid.startCumulativeMps;
    }

    /// @notice Convert a bid to a demand
    /// @dev The demand is scaled based on the remaining mps such that it is fully allocated over the remaining parts of the auction
    /// @param bid The bid to convert
    /// @return demand The demand struct representing the bid
    function toDemand(Bid memory bid) internal pure returns (Demand memory demand) {
        ValueX7 bidDemandOverRemainingAuctionX7 =
            bid.amount.scaleUpToX7().mulUint256(MPSLib.MPS).divUint256(bid.mpsRemainingInAuction());
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
