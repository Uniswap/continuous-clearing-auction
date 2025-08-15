// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {DemandLib} from './DemandLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint64 withdrawnBlock; // Block number when the bid was withdrawn
    uint128 tickId; // The tick id of the bid
    address owner; // Who is allowed to withdraw the bid
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
    /// @return The demand of the bid
    function demand(Bid memory bid, uint256 price) internal pure returns (uint256) {
        return bid.exactIn ? bid.amount.resolveCurrencyDemand(price) : bid.amount;
    }
}
