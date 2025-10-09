// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract ToEffectiveAmountTest is BttBase {
    function test_WhenCalledWithBid(uint24 _startCumulativeMps, uint256 _amount) external {
        // it returns bid.amount * mps / (mps - bid.startCumulativeMps)

        uint24 startCumulativeMps = uint24(bound(_startCumulativeMps, 0, ConstantsLib.MPS - 1));
        uint256 amount = bound(_amount, 0, BidLib.MAX_BID_AMOUNT);

        Bid memory bid;
        bid.startCumulativeMps = startCumulativeMps;
        bid.amount = amount;

        ValueX7 result = BidLib.toEffectiveAmount(bid);
        assertEq(result, ValueX7.wrap(amount * 1e7 * ConstantsLib.MPS / (ConstantsLib.MPS - startCumulativeMps)));
    }
}
