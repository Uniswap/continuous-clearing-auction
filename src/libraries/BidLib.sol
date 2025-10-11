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
    uint256 amountX128; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

/// @title BidLib
library BidLib {
    using ValueX7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    error BidMustBeAboveClearingPrice();
    error InvalidBidPriceTooHigh();
    error InvalidBidAmountTooHigh();

    /// @notice The minimum allowable amount for a bid such that is not rounded down to zero
    uint128 public constant MIN_BID_AMOUNT = 1e7;
    /// @notice The maximum allowable price for a bid, defined as the square of MAX_SQRT_PRICE from Uniswap v4's TickMath library.
    uint256 public constant MAX_BID_PRICE =
        26_957_920_004_054_754_506_022_898_809_067_591_261_277_585_227_686_421_694_841_721_768_917;

    function validate(Bid memory bid, uint256 _clearingPrice, uint256 _totalSupply) internal pure {
        if (bid.maxPrice <= _clearingPrice) revert BidMustBeAboveClearingPrice();
        // An operation in the code which can overflow a uint256 is TOTAL_SUPPLY * (maxPrice / Q96) * Q128.
        // This is only possible if bid.maxPrice is greater than Q96 since then the division is > 1
        // and when multiplied by the total supply can exceed type(uint128).max, which would overflow when multiplied by Q128.
        if (
            (
                bid.maxPrice > FixedPoint96.Q96
                    && _totalSupply.fullMulDiv(bid.maxPrice, FixedPoint96.Q96) > type(uint256).max.fromX128()
            ) || bid.maxPrice >= MAX_BID_PRICE
        ) revert InvalidBidPriceTooHigh();
        // If the bid amount after scaling to 128.128 exceeds ConstantsLib.X7_UPPER_BOUND, revert
        if (bid.amountX128 > ConstantsLib.X7_UPPER_BOUND) revert InvalidBidAmountTooHigh();
    }

    function toX128(uint128 _amount) internal pure returns (uint256) {
        // Guaranteed to not overflow a uint256
        unchecked {
            return uint256(_amount) * FixedPoint128.Q128;
        }
    }

    function fromX128(uint256 _amount) internal pure returns (uint128) {
        // This will truncate all lower 128 bits
        unchecked {
            return uint128(_amount / FixedPoint128.Q128);
        }
    }

    /// @notice Calculate the number of mps remaining in the auction since the bid was submitted
    /// @param bid The bid to calculate the remaining mps for
    /// @return The number of mps remaining in the auction
    function mpsRemainingInAuctionAfterSubmission(Bid memory bid) internal pure returns (uint24) {
        return ConstantsLib.MPS - bid.startCumulativeMps;
    }

    /// @notice Convert a bid amount to its effective amount over the remaining percentage of the auction
    /// TODO(ez): fix natspec
    function toEffectiveAmount(Bid memory bid) internal pure returns (uint256) {
        return bid.amountX128.fullMulDiv(ConstantsLib.MPS, bid.mpsRemainingInAuctionAfterSubmission());
    }
}
