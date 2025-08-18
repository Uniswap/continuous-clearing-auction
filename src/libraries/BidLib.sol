// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {DemandLib} from './DemandLib.sol';
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
    using FixedPointMathLib for uint256;
    using DemandLib for uint256;
    using BidLib for Bid;
    using SafeCastLib for uint256;

    error InvalidBidPrice();

    /// @notice Validate a bid
    /// @dev The bid must be greater than the clearing price and at a tick boundary
    /// @param maxPrice The max price of the bid
    /// @param clearingPrice The clearing price of the auction
    /// @param tickSpacing The tick spacing of the auction
    function validate(uint256 maxPrice, uint256 clearingPrice, uint256 tickSpacing) internal pure {
        if (maxPrice <= clearingPrice || maxPrice % tickSpacing != 0) {
            revert InvalidBidPrice();
        }
    }

    /// @notice Resolve the demand of a bid
    /// @param bid The bid
    /// @param price The price of the bid
    /// @return The demand of the bid
    function demand(Bid memory bid, uint256 price) internal pure returns (uint256) {
        return bid.exactIn ? bid.amount.resolveCurrencyDemand(price) : bid.amount;
    }

    /// @notice Calculate the tokens filled and refund of a bid which has been fully filled
    /// @param bid bid
    /// @param cumulativeMpsPerPriceDelta The cumulative mps per price delta
    /// @param cumulativeMpsDelta The cumulative mps delta
    /// @return tokensFilled The amount of tokens filled
    function calculateFill(
        Bid memory bid,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) internal pure returns (uint256 tokensFilled) {
        if (bid.exactIn) {
            // TODO: removed PRECISION
            tokensFilled = bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, mpsDenominator);
        } else {
            tokensFilled = bid.amount.applyMpsDenominator(cumulativeMpsDelta, mpsDenominator);
        }
    }

    /// @notice Calculate the refund of a bid
    /// @param bid The bid
    /// @param maxPrice The max price of the bid
    /// @param tokensFilled The amount of tokens filled
    /// @param cumulativeMpsDelta The cumulative mps delta
    /// @return refund The amount of currency refunded
    function calculateRefund(
        Bid memory bid,
        uint256 maxPrice,
        uint256 tokensFilled,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) internal pure returns (uint256 refund) {
        return bid.exactIn
            ? bid.amount - bid.amount.applyMpsDenominator(cumulativeMpsDelta, mpsDenominator)
            : maxPrice * (bid.amount - tokensFilled);
    }

    /// @notice Calculate the tokens filled and proportion of input used for a partially filled bid
    /// @param bidDemand The resolved demand of the bid at the tick price
    /// @param tickDemand The resolved demand at the tick
    /// @param supply The supply of the auction being sold
    /// @param mpsDelta The mps of the totalSupply that is being sold
    /// @param resolvedDemandAboveClearingPrice The resolved demand above the clearing price
    /// @return tokensFilled The amount of tokens filled
    function calculatePartialFill(
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 supply,
        uint24 mpsDelta,
        uint256 resolvedDemandAboveClearingPrice
    ) internal pure returns (uint256 tokensFilled, uint24 cumulativeMpsDelta) {
        uint256 _tickDemandMps = tickDemand.applyMps(mpsDelta);
        uint256 supplySoldToTick = supply - resolvedDemandAboveClearingPrice.applyMps(mpsDelta);
        tokensFilled = supplySoldToTick.fullMulDiv(bidDemand.applyMps(mpsDelta), _tickDemandMps);
        cumulativeMpsDelta = (uint256(mpsDelta).fullMulDiv(supplySoldToTick, _tickDemandMps)).toUint24();
    }
}
