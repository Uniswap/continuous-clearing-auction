// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint64 withdrawnBlock; // Block number when the bid was withdrawn
    int24 tick;
    address owner; // Who is allowed to withdraw the bid
    uint256 amount; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

library BidLib {
    using AuctionStepLib for uint256;
    using FixedPointMathLib for uint256;

    error InvalidBidPrice();

    uint256 public constant PRECISION = 1e18;

    /// @notice Validate a bid
    /// @param maxPrice The max price of the bid
    /// @param floorPrice The floor price of the auction
    /// @param tickSpacing The tick spacing of the auction
    /// @dev The bid must be greater than or equal to the floor price, less than or equal to the maximum price,
    /// and divisible by the tick spacing
    function validate(uint256 maxPrice, uint256 floorPrice, uint256 tickSpacing) internal pure {
        if (maxPrice < floorPrice || maxPrice % tickSpacing != 0) {
            revert InvalidBidPrice();
        }
    }

    /// @notice Resolve a bid
    function resolve(Bid memory bid, uint256 maxPrice, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        internal
        pure
        returns (uint256 tokensFilled, uint256 refund)
    {
        if (bid.exactIn) {
            tokensFilled = bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, PRECISION * AuctionStepLib.MPS);
            refund = bid.amount - bid.amount.applyMps(cumulativeMpsDelta);
        } else {
            tokensFilled = bid.amount.applyMps(cumulativeMpsDelta);
            refund = maxPrice * (bid.amount - tokensFilled);
        }
    }
}
