// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';

import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract ToEffectiveAmountTest is BttBase {
    function test_WhenCalledWithBid(uint24 _startCumulativeMps, uint128 _amount) external pure {
        // it returns bid.amount * mps / (mps - bid.startCumulativeMps)

        uint24 startCumulativeMps = uint24(bound(_startCumulativeMps, 0, ConstantsLib.MPS - 1));
        uint256 amountQ96 = _amount << FixedPoint96.RESOLUTION;

        Bid memory bid;
        bid.startCumulativeMps = startCumulativeMps;
        bid.amountQ96 = amountQ96;

        uint256 result = BidLib.toEffectiveAmount(bid);
        assertEq(result, amountQ96 * ConstantsLib.MPS / (ConstantsLib.MPS - startCumulativeMps));
    }
}
