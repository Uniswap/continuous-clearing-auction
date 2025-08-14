// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Bid, BidLib} from '../../src/libraries/BidLib.sol';

contract MockBidLib {
    function calculateFill(
        Bid memory bid,
        uint256 maxPrice,
        uint256 tickSpacing,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) external pure returns (uint256 tokensFilled, uint256 refund) {
        return BidLib.calculateFill(
            bid, maxPrice, tickSpacing, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, mpsDenominator
        );
    }
}
