// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'continuous-clearing-auction/libraries/BidLib.sol';
import {CheckpointAccountingLib} from 'continuous-clearing-auction/libraries/CheckpointAccountingLib.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {ValueX7} from 'continuous-clearing-auction/libraries/ValueX7Lib.sol';

contract AccountPartiallyFilledCheckpointsTest is BttBase {
    // should never happen but we catch it in the code to avoid div by 0
    function test_WhenTickDemandEQ0(Bid memory _bid, ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7) external {
        // it returns (0, 0)

        (uint256 tokensFilled, uint256 currencySpent) = CheckpointAccountingLib.accountPartiallyFilledCheckpoints(
            _bid, 0, _cumulativeCurrencyRaisedAtClearingPriceQ96_X7
        );

        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    modifier givenTickDemandGT0() {
        _;
    }

    function test_WhenCurrencySpentRoundsDownToZero(Bid memory _bid, uint256 _tickDemand) external givenTickDemandGT0 {
        // it returns 1 currency spent

        // assume reasonable bounds
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _bid.maxPrice = bound(_bid.maxPrice, 1, ConstantsLib.MAX_BID_PRICE);
        // Small numerator
        _bid.amountQ96 = 1;
        ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(1);
        // Larger denominator, and we know that mpsAfterSubmission must always be >= 1
        _tickDemand = 2;

        // so at the very least we have 1 * 1 / (2 * mpsAfterSubmission) , which rounds down to 0.

        (, uint256 currencySpent) = CheckpointAccountingLib.accountPartiallyFilledCheckpoints(
            _bid, _tickDemand, _cumulativeCurrencyRaisedAtClearingPriceQ96_X7
        );

        // Currency spent should be rounded down to 0 but its rounded up to 1
        assertEq(currencySpent, 1);
    }

    function test_WhenTokensFilledRoundsDownToZero(Bid memory _bid, uint256 _tickDemand) external givenTickDemandGT0 {
        // it returns 0 tokens filled

        // assume reasonable bounds
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        // Set bid max price to 1 to avoid any additional rounding down
        _bid.maxPrice = 1;
        // Small numerator
        _bid.amountQ96 = 1;
        ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(1);
        // Larger denominator, and we know that mpsAfterSubmission must always be >= 1
        _tickDemand = 2;

        // so at the very least we have 1 * 1 / (2 * mpsAfterSubmission) , which rounds down to 0.

        (uint256 tokensFilled,) = CheckpointAccountingLib.accountPartiallyFilledCheckpoints(
            _bid, _tickDemand, _cumulativeCurrencyRaisedAtClearingPriceQ96_X7
        );

        // Tokens filled should be rounded down
        assertEq(tokensFilled, 0);
    }
}
