// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint128} from './FixedPoint128.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Bid {
    uint64 startBlock; // Block number when the bid was first made in
    uint24 startCumulativeMps; // Cumulative mps at the start of the bid
    uint64 exitedBlock; // Block number when the bid was exited
    uint256 maxPrice; // The max price of the bid
    address owner; // Who is allowed to exit the bid
    uint256 amountQ96; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

/// @title BidLib
library BidLib {
    using ValueX7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    /// @dev Error thrown when a bid is submitted with no remaining percentage of the auction
    ///      This is prevented by the auction contract as bids cannot be submitted when the auction is sold out,
    ///      but we catch it instead of reverting with division by zero.
    error MpsRemainingIsZero();

    /// @notice Calculate the number of mps remaining in the auction since the bid was submitted
    /// @param bid The bid to calculate the remaining mps for
    /// @return The number of mps remaining in the auction
    function mpsRemainingInAuctionAfterSubmission(Bid memory bid) internal pure returns (uint24) {
        return ConstantsLib.MPS - bid.startCumulativeMps;
    }

    /// @notice Scale a bid amount to its effective amount over the remaining percentage of the auction
    ///         This is an important normalization step to ensure that we can calculate the currencyRaised
    ///         when cumulative demand is less than supply using the original supply schedule.
    /// @param bid The bid to scale
    /// @return The scaled amount
    function toEffectiveAmount(Bid memory bid) internal pure returns (uint256) {
        uint24 mpsRemainingInAuction = bid.mpsRemainingInAuctionAfterSubmission();
        if (mpsRemainingInAuction == 0) revert MpsRemainingIsZero();
        return bid.amountQ96 * ConstantsLib.MPS / mpsRemainingInAuction;
    }
}
