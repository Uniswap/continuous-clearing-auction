// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {DemandLib} from './DemandLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint64 withdrawnBlock; // Block number when the bid was withdrawn
    uint128 tickId; // The tick id of the bid
    address owner; // Who is allowed to withdraw the bid
    uint256 amount; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

library BidLib {
    using AuctionStepLib for uint256;
    using FixedPointMathLib for uint256;
    using DemandLib for uint256;
    using BidLib for Bid;

    error InvalidBidPrice();

    uint256 public constant PRECISION = 1e18;

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
    /// @param tickSpacing The tick spacing of the auction
    /// @return The demand of the bid
    function demand(Bid memory bid, uint256 price, uint256 tickSpacing) internal pure returns (uint256) {
        return bid.exactIn ? bid.amount.resolveCurrencyDemand(price, tickSpacing) : bid.amount;
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
            tokensFilled = bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, PRECISION * AuctionStepLib.MPS);
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
}
