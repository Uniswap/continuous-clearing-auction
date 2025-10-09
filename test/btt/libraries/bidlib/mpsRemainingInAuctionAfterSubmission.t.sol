// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';

contract MpsRemainingInAuctionAfterSubmissionTest is BttBase {
    function test_WhenCalledWithBid(uint24 _startCumulativeMps) external {
        // it returns mps - bid.startCumulativeMps

        uint24 startCumulativeMps = uint24(bound(_startCumulativeMps, 0, ConstantsLib.MPS));

        Bid memory bid;
        bid.startCumulativeMps = startCumulativeMps;

        uint24 result = BidLib.mpsRemainingInAuctionAfterSubmission(bid);

        assertEq(result, ConstantsLib.MPS - startCumulativeMps);
    }
}
