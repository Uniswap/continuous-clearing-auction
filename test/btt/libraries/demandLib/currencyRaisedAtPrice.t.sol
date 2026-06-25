// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ConstantsLib} from '../../../../src/libraries/ConstantsLib.sol';
import {DemandLib} from '../../../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../../../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../../../../src/libraries/ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract CurrencyRaisedAtPriceTest is BttBase {
    // --- Unit tests ---

    function test_WhenDemandAtPriceIs0(
        uint128 _remainingSupplyQ96X7,
        uint128 _demandAbovePriceQ96,
        uint128 _priceQ96,
        uint24 _deltaMps,
        uint24 _remainingMps
    ) external pure {
        // it returns 0

        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 demandAbovePriceQ96 = bound(_demandAbovePriceQ96, 0, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint256 deltaMps = bound(_deltaMps, 1, ConstantsLib.MPS);
        uint256 remainingMps = bound(_remainingMps, deltaMps, ConstantsLib.MPS);

        ValueX7 result = DemandLib.currencyRaisedAtPrice(
            ValueX7.wrap(remainingSupplyQ96X7), 0, demandAbovePriceQ96, priceQ96, deltaMps, remainingMps
        );

        assertEq(ValueX7.unwrap(result), 0);
    }

    function test_WhenDemandAboveCoversTotal(
        uint128 _remainingSupplyQ96X7,
        uint128 _demandAtPriceQ96,
        uint128 _priceQ96,
        uint24 _deltaMps,
        uint24 _remainingMps
    ) external pure {
        // it returns 0

        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 demandAtPriceQ96 = bound(_demandAtPriceQ96, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint256 deltaMps = bound(_deltaMps, 1, ConstantsLib.MPS);
        uint256 remainingMps = bound(_remainingMps, deltaMps, ConstantsLib.MPS);

        uint256 totalCurrencyRaisedQ96X7 =
            FixedPointMathLib.fullMulDivUp(remainingSupplyQ96X7, priceQ96 * deltaMps, FixedPoint96.Q96 * remainingMps);
        // demandAbove * deltaMps must be >= totalCurrencyRaised so saturatingSub yields 0
        vm.assume(deltaMps > 0);
        uint256 demandAbovePriceQ96 = totalCurrencyRaisedQ96X7 / deltaMps;
        vm.assume(demandAbovePriceQ96 * deltaMps >= totalCurrencyRaisedQ96X7);
        vm.assume(demandAbovePriceQ96 <= ConstantsLib.X7_UPPER_BOUND);

        ValueX7 result = DemandLib.currencyRaisedAtPrice(
            ValueX7.wrap(remainingSupplyQ96X7), demandAtPriceQ96, demandAbovePriceQ96, priceQ96, deltaMps, remainingMps
        );

        assertEq(ValueX7.unwrap(result), 0);
    }

    function test_WhenBidsAtClearingArePartiallyFilled() external pure {
        // it returns only what remains after bids above clearing are accounted for

        uint256 totalSupply = 1000e18;
        uint256 remainingSupplyQ96X7 = totalSupply * ConstantsLib.MPS * FixedPoint96.Q96;
        uint256 priceQ96 = FixedPoint96.Q96;
        uint256 deltaMps = 100_000;
        uint256 remainingMps = ConstantsLib.MPS;

        // 90% of demand is above clearing, 80% at clearing — bids at clearing far exceed what the auction needs
        uint256 demandAbovePriceQ96 = totalSupply * priceQ96 * 9 / 10;
        uint256 demandAtPriceQ96 = totalSupply * priceQ96 * 8 / 10;

        ValueX7 result = DemandLib.currencyRaisedAtPrice(
            ValueX7.wrap(remainingSupplyQ96X7), demandAtPriceQ96, demandAbovePriceQ96, priceQ96, deltaMps, remainingMps
        );

        uint256 totalCurrencyRaisedQ96X7 = totalSupply * priceQ96 * deltaMps;
        uint256 amountFromBidsAboveClearingQ96X7 = demandAbovePriceQ96 * deltaMps;
        uint256 expectedAtClearing = totalCurrencyRaisedQ96X7 - amountFromBidsAboveClearingQ96X7;

        // Bids at clearing can provide far more than needed — only the remainder is used
        assertLt(expectedAtClearing, demandAtPriceQ96 * deltaMps);
        assertEq(ValueX7.unwrap(result), expectedAtClearing);
    }

    function test_WhenBidsAtClearingAreCappedByRoundedUpPrice() external pure {
        // it returns demandAtPrice * deltaMps

        uint256 totalSupply = 1000e18;
        uint256 remainingSupplyQ96X7 = totalSupply * ConstantsLib.MPS * FixedPoint96.Q96;
        uint256 priceQ96 = FixedPoint96.Q96;
        uint256 deltaMps = 100_000;
        uint256 remainingMps = ConstantsLib.MPS;

        // 99% of demand is from bids above clearing, only 1 wei of demand at clearing
        uint256 demandAbovePriceQ96 = totalSupply * priceQ96 * 99 / 100;
        uint256 demandAtPriceQ96 = 1;

        ValueX7 result = DemandLib.currencyRaisedAtPrice(
            ValueX7.wrap(remainingSupplyQ96X7), demandAtPriceQ96, demandAbovePriceQ96, priceQ96, deltaMps, remainingMps
        );

        assertEq(ValueX7.unwrap(result), demandAtPriceQ96 * deltaMps);
    }

    // --- Fuzz tests ---

    function test_NeverExceedsDemandAtPriceTimesDeltaMps(
        uint128 _remainingSupplyQ96X7,
        uint128 _demandAtPriceQ96,
        uint128 _demandAbovePriceQ96,
        uint128 _priceQ96,
        uint24 _deltaMps,
        uint24 _remainingMps
    ) external pure {
        // it never exceeds demandAtPrice * deltaMps

        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 demandAtPriceQ96 = bound(_demandAtPriceQ96, 0, ConstantsLib.X7_UPPER_BOUND);
        uint256 demandAbovePriceQ96 = bound(_demandAbovePriceQ96, 0, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint256 deltaMps = bound(_deltaMps, 1, ConstantsLib.MPS);
        uint256 remainingMps = bound(_remainingMps, deltaMps, ConstantsLib.MPS);

        ValueX7 result = DemandLib.currencyRaisedAtPrice(
            ValueX7.wrap(remainingSupplyQ96X7), demandAtPriceQ96, demandAbovePriceQ96, priceQ96, deltaMps, remainingMps
        );

        assertLe(ValueX7.unwrap(result), demandAtPriceQ96 * deltaMps);
    }
}
