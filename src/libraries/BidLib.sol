// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint128 maxPrice; // Max clearing price
    address owner; // Who is allowed to withdraw the bid
    uint256 amount; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
    uint256 startBlock; // Block number when the bid was first made in
    uint256 withdrawnBlock; // Block number when the bid was withdrawn
}

library BidLib {
    using AuctionStepLib for uint256;

    error InvalidBidPrice();

    /// @notice Validate a bid
    /// @param bid The bid to validate
    /// @param floorPrice The floor price of the auction
    /// @param tickSpacing The tick spacing of the auction
    /// @dev The bid must be greater than or equal to the floor price, less than or equal to the maximum price,
    /// and divisible by the tick spacing
    function validate(Bid memory bid, uint256 floorPrice, uint256 tickSpacing) internal pure {
        if (bid.maxPrice < floorPrice || bid.maxPrice > type(uint128).max || bid.maxPrice % tickSpacing != 0) {
            revert InvalidBidPrice();
        }
    }

    /// @notice Resolve a bid
    function resolve(Bid memory bid, uint16 cumulativeBpsPerPriceDelta, uint16 cumulativeBpsDelta) internal pure returns (uint256 tokensFilled, uint256 refund) {
        if (bid.exactIn) {
            tokensFilled = bid.amount.applyBps(cumulativeBpsPerPriceDelta);
            refund = bid.amount - bid.amount.applyBps(cumulativeBpsDelta);
        } else {
            tokensFilled = bid.amount.applyBps(cumulativeBpsDelta);
            refund = bid.maxPrice * (bid.amount - tokensFilled);
        }
    }
}
