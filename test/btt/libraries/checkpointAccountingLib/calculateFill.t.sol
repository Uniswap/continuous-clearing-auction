// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {Bid, BidLib} from 'continuous-clearing-auction/libraries/BidLib.sol';
import {CheckpointAccountingLib} from 'continuous-clearing-auction/libraries/CheckpointAccountingLib.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract CalculateFillTest is BttBase {
    using FixedPointMathLib for *;

    function test_WhenBidAmountQ96EQ0(Bid memory _bid, uint256 _cumulativeMpsPerPriceDelta, uint24 _cumulativeMpsDelta)
        external
    {
        // it returns 0 tokens filled and 0 currency spent

        // reasonable bounds
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));

        // it returns 0 tokens filled and 0 currency spent
        _bid.amountQ96 = 0;
        (uint256 tokensFilled, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(_bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);
        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    modifier whenBidAmountQ96GT0() {
        _;
    }

    // Not possible to have zero cumulativeMpsDelta and non zero cumulativeMpsPerPriceDelta, shown in `accountFullyFilledCheckpoints` test
    function test_WhenCumulativeMpsDeltaEQ0AndCumulativeMpsPerPriceDeltaEQ0(Bid memory _bid)
        external
        whenBidAmountQ96GT0
    {
        // it returns 0 tokens filled and 0 currency spent

        // reasonable bounds
        _bid.amountQ96 = bound(_bid.amountQ96, 1, type(uint128).max);
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));

        // it returns 0 tokens filled and 1 currency spent
        uint24 cumulativeMpsDelta = 0;
        uint256 cumulativeMpsPerPriceDelta = 0;
        (uint256 tokensFilled, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(_bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta);
        assertEq(currencySpent, 0);
        assertEq(tokensFilled, 0);
    }

    modifier whenCumulativeMpsDeltaGT0AndCumulativeMpsPerPriceDeltaGT0() {
        _;
    }

    function test_WhenCurrencySpentRoundsDownToZero(
        Bid memory _bid,
        uint256 _cumulativeMpsPerPriceDelta,
        uint24 _cumulativeMpsDelta
    ) external whenBidAmountQ96GT0 whenCumulativeMpsDeltaGT0AndCumulativeMpsPerPriceDeltaGT0 {
        // it returns 1 currency spent

        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _cumulativeMpsDelta = uint24(bound(_cumulativeMpsDelta, 1, ConstantsLib.MPS));
        // Very small amountQ96
        _bid.amountQ96 = 1;

        // Assume that mps remaining in auction after submission is greater than cumulativeMpsDelta
        // such that the currency spent should be rounded down to zero
        vm.assume(_cumulativeMpsDelta < BidLib.mpsRemainingInAuctionAfterSubmission(_bid));

        // don't check tokens filled bc depends on cumulativeMpsPerPriceDelta
        (, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(_bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);
        // Assert that currency spent is rounded up, even though it would be rounded down to zero
        assertEq(currencySpent, 1);
    }

    function test_WhenTokensFilledRoundsDownToZero(Bid memory _bid, uint24 _cumulativeMpsDelta)
        external
        whenBidAmountQ96GT0
        whenCumulativeMpsDeltaGT0AndCumulativeMpsPerPriceDeltaGT0
    {
        // it returns 0 tokens filled

        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        // Very small amountQ96
        _bid.amountQ96 = 1;
        // Have the numerator be one less than the denominator
        uint256 _cumulativeMpsPerPriceDelta =
            ((FixedPoint96.Q96 << FixedPoint96.RESOLUTION) * BidLib.mpsRemainingInAuctionAfterSubmission(_bid)) - 1;

        (uint256 tokensFilled,) =
            CheckpointAccountingLib.calculateFill(_bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);
        assertEq(tokensFilled, 0);
    }
}
