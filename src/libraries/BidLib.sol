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
    uint256 amountQ96; // User's demand
    uint256 tokensFilled; // Amount of tokens filled
}

/// @title BidLib
library BidLib {
    using ValueX7Lib for *;
    using BidLib for *;
    using FixedPointMathLib for *;

    error InvalidBidAmountTooLarge();
    error BidMustBeAboveClearingPrice();
    error InvalidBidPriceTooHigh();

    function validate(uint256 _maxPrice, uint128 _amount, uint256 _clearingPrice, uint256 _totalSupply) internal pure {
        if (_amount > ConstantsLib.MAX_AMOUNT) revert InvalidBidAmountTooLarge();
        if (_maxPrice <= _clearingPrice) revert BidMustBeAboveClearingPrice();
        // An operation in the code which can overflow a uint256 is TOTAL_SUPPLY * (maxPrice / Q96) * Q96.
        // This is only possible if bid.maxPrice is greater than Q96 since then the division is > 1
        // and when multiplied by the total supply can exceed type(uint128).max, which would overflow when multiplied by Q96.
        if (
            _maxPrice > FixedPoint96.Q96
                && _totalSupply.fullMulDiv(_maxPrice, FixedPoint96.Q96) > type(uint256).max / FixedPoint96.Q96
        ) revert InvalidBidPriceTooHigh();
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
        return bid.amountQ96.fullMulDiv(ConstantsLib.MPS, bid.mpsRemainingInAuctionAfterSubmission());
    }
}
