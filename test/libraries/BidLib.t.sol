// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {Test} from 'forge-std/Test.sol';

contract BidLibTest is Test {
    using BidLib for *;

    /// forge-config: default.allow_internal_expect_revert = true
    /// forge-config: ci.allow_internal_expect_revert = true
    function test_toEffectiveAmount(Bid memory _bid) public {
        vm.assume(_bid.startCumulativeMps <= ConstantsLib.MPS);
        vm.assume(_bid.amountQ96 < type(uint256).max / ConstantsLib.MPS);
        if (_bid.mpsRemainingInAuctionAfterSubmission() == 0) {
            vm.expectRevert(BidLib.MpsRemainingIsZero.selector);
            _bid.toEffectiveAmount();
        } else {
            assertEq(
                _bid.toEffectiveAmount(),
                (_bid.amountQ96 * ConstantsLib.MPS) / _bid.mpsRemainingInAuctionAfterSubmission()
            );
        }
    }
}
