// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid, BidLib} from 'continuous-clearing-auction/libraries/BidLib.sol';

contract MockBidLib {
    function mpsRemainingInAuctionAfterSubmission(Bid memory _bid) external pure returns (uint24) {
        return BidLib.mpsRemainingInAuctionAfterSubmission(_bid);
    }

    function toEffectiveAmount(Bid memory _bid) external pure returns (uint256) {
        return BidLib.toEffectiveAmount(_bid);
    }
}
