// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';

import {MockBidLib} from 'btt/mocks/MockBidLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';

contract ToEffectiveAmountTest is BttBase {
    MockBidLib internal mockBidLib;

    function setUp() external {
        mockBidLib = new MockBidLib();
    }

    function test_WhenRemainingMpsEQ0(Bid memory _bid) external {
        // it reverts with {MpsRemainingIsZero}

        // We should not hit this case ever, but it fails explicitly instead of
        // due to division by zero
        _bid.startCumulativeMps = ConstantsLib.MPS;

        vm.expectRevert(BidLib.MpsRemainingIsZero.selector);
        mockBidLib.toEffectiveAmount(_bid);
    }

    function test_WhenRemainingMpsNEQ0(uint24 _startCumulativeMps, uint128 _amount) external view {
        // it returns bid.amount * mps / (mps - bid.startCumulativeMps)

        uint24 startCumulativeMps = uint24(bound(_startCumulativeMps, 0, ConstantsLib.MPS - 1));
        uint256 amountQ96 = _amount << FixedPoint96.RESOLUTION;

        Bid memory bid;
        bid.startCumulativeMps = startCumulativeMps;
        bid.amountQ96 = amountQ96;

        uint256 result = mockBidLib.toEffectiveAmount(bid);
        assertEq(result, amountQ96 * ConstantsLib.MPS / (ConstantsLib.MPS - startCumulativeMps));
    }
}
