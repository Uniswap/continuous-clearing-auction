// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {DemandLib} from './DemandLib.sol';

import {FixedPoint96} from './FixedPoint96.sol';
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
    using DemandLib for uint256;
    using BidLib for Bid;
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    uint256 public constant PRECISION = 1e18;

    /// @notice Resolve the demand of a bid at its maxPrice
    /// @param bid The bid
    /// @return The demand of the bid
    function demand(Bid memory bid, bool currencyIsToken0) internal pure returns (uint256) {
        return bid.exactIn ? bid.amount.resolveCurrencyDemand(bid.maxPrice, currencyIsToken0) : bid.amount;
    }

    /// @notice Calculate the input amount required for an amount and maxPrice
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param maxPrice The max price of the bid
    /// @return The input amount required for an amount and maxPrice
    function inputAmount(bool exactIn, uint256 amount, uint256 maxPrice, bool currencyIsToken0)
        internal
        pure
        returns (uint256)
    {
        if (exactIn) return amount;
        if (currencyIsToken0) {
            return amount.fullMulDivUp(FixedPoint96.Q96, maxPrice);
        } else {
            return amount.fullMulDivUp(maxPrice, FixedPoint96.Q96);
        }
    }

    /// @notice Calculate the input amount required to place the bid
    /// @param bid The bid
    /// @return The input amount required to place the bid
    function inputAmount(Bid memory bid, bool currencyIsToken0) internal pure returns (uint256) {
        return inputAmount(bid.exactIn, bid.amount, bid.maxPrice, currencyIsToken0);
    }
}
