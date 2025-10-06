// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './ValueX7X7Lib.sol';
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
    using ValueX7X7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    /// @notice The minimum allowable amount for a bid such that is not rounded down to zero
    uint256 public constant MIN_BID_AMOUNT = ValueX7Lib.X7;
    /// @notice The maximum allowable amount for a bid such that it will not overflow a ValueX7X7 value
    uint256 public constant MAX_BID_AMOUNT = ConstantsLib.X7X7_UPPER_BOUND - 1;
    /// @notice The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.
    uint256 public constant MAX_BID_PRICE =
        26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917;

    /// @notice Calculate the number of mps remaining in the auction since the bid was submitted
    /// @param bid The bid to calculate the remaining mps for
    /// @return The number of mps remaining in the auction
    function mpsRemainingInAuctionAfterSubmission(Bid memory bid) internal pure returns (uint24) {
        return ConstantsLib.MPS - bid.startCumulativeMps;
    }

    /// @notice Scale a bid amount to its effective amount over the remaining percentage of the auction
    /// @dev The amount is scaled based on the remaining mps such that it is fully allocated over the remaining parts of the auction
    ///      It is not possible to avoid the division here because we must include the scaled up demand
    ///      into tick demand and `sumCurrencyDemandAboveClearingX7` where we have no way to preserve the bid-level information.
    /// @param bid The bid to convert
    /// @return bidAmountOverRemainingAuctionX7 The bid amount in ValueX7 scaled to the remaining percentage of the auction
    function toEffectiveAmount(Bid memory bid) internal pure returns (ValueX7 bidAmountOverRemainingAuctionX7) {
        bidAmountOverRemainingAuctionX7 =
            bid.amount.scaleUpToX7().mulUint256(ConstantsLib.MPS).divUint256(bid.mpsRemainingInAuctionAfterSubmission());
    }
}
