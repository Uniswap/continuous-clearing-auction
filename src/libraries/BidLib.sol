// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Bid {
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
    using ValueX7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    /// @notice The minimum allowable amount for a bid such that is not rounded down to zero
    uint128 public constant MIN_BID_AMOUNT = 1e7;
    /// @notice The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.
    uint256 public constant MAX_BID_PRICE =
        26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917;

    /// @notice Calculate the number of mps remaining in the auction since the bid was submitted
    /// @param bid The bid to calculate the remaining mps for
    /// @return The number of mps remaining in the auction
    function mpsRemainingInAuctionAfterSubmission(Bid memory bid) internal pure returns (uint24) {
        return ConstantsLib.MPS - bid.startCumulativeMps;
    }

    /// @notice Convert a bid amount to its effective amount over the remaining percentage of the auction
    /// TODO(ez): fix natspec
    function toEffectiveAmount(Bid memory bid) internal pure returns (uint256) {
        return bid.amount.fullMulDiv(ConstantsLib.MPS, bid.mpsRemainingInAuctionAfterSubmission());
    }
}
