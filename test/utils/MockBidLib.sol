// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Bid, BidLib} from '../../src/libraries/BidLib.sol';

contract MockBidLib {
    function calculateFill(
        Bid memory bid,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) external pure returns (uint256 tokensFilled) {
        return BidLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, mpsDenominator);
    }

    function calculateRefund(
        Bid memory bid,
        uint256 maxPrice,
        uint256 tokensFilled,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) external pure returns (uint256 refund) {
        return BidLib.calculateRefund(bid, maxPrice, tokensFilled, cumulativeMpsDelta, mpsDenominator);
    }
}
