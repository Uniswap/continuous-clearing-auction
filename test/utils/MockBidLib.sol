// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BidLib, Bid} from '../../src/libraries/BidLib.sol';

contract MockBidLib {
    function resolve(Bid memory bid, uint256 cumulativeBpsPerPriceDelta, uint16 cumulativeBpsDelta) external pure returns (uint256 tokensFilled, uint256 refund) {
        return BidLib.resolve(bid, cumulativeBpsPerPriceDelta, cumulativeBpsDelta); 
    }
}