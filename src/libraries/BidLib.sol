// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Bid {
    bool exactIn; // If amount below is denoted in currency or tokens
    uint64 startBlock; // Block number when the bid was first made in
    uint64 withdrawnBlock; // Block number when the bid was withdrawn
    address owner; // Who is allowed to withdraw the bid
    uint256 amount; // User's demand
}

library BidLib {
    error InvalidBidPrice();

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
}
