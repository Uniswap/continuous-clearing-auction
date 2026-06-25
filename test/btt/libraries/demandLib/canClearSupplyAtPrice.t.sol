// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ConstantsLib} from '../../../../src/libraries/ConstantsLib.sol';
import {DemandLib} from '../../../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../../../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../../../../src/libraries/ValueX7Lib.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {BttBase} from 'btt/BttBase.sol';

contract CanClearSupplyAtPriceTest is BttBase {
    // --- Explicit 512-bit comparison branch coverage ---

    function test_WhenHighLhs_GT_HighRhs() external pure {
        // it returns true

        // demand * remainingMps * Q96 must overflow 2^256 → need demand * remainingMps > 2^160
        uint256 demandQ96 = 1 << 200;
        uint256 remainingMps = ConstantsLib.MPS;
        // Small supply * price keeps highRhs == 0
        uint256 remainingSupplyQ96X7 = 1;
        uint256 priceQ96 = 1;

        (uint256 highLhs,) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs,) = Math.mul512(remainingSupplyQ96X7, priceQ96);
        assertGt(highLhs, highRhs);

        assertTrue(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenHighLhsEQHighRhs_And_LowLhs_GT_LowRhs() external pure {
        // it returns true

        // demand * remainingMps == supply, price == Q96 → high words match (both 0)
        // Then add 1 to demand so lowLhs > lowRhs while high words stay equal.
        uint256 remainingSupplyQ96X7 = 1000;
        uint256 priceQ96 = FixedPoint96.Q96;
        uint256 remainingMps = 1;
        uint256 demandQ96 = remainingSupplyQ96X7 + 1;

        (uint256 highLhs, uint256 lowLhs) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(remainingSupplyQ96X7, priceQ96);
        assertEq(highLhs, highRhs);
        assertGt(lowLhs, lowRhs);

        assertTrue(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenHighLhsEQHighRhs_And_LowLhsEQLowRhs() external pure {
        // it returns true

        // Exact equality: demand * remainingMps == supply, price == Q96
        uint256 remainingSupplyQ96X7 = 1000;
        uint256 priceQ96 = FixedPoint96.Q96;
        uint256 remainingMps = 1;
        uint256 demandQ96 = remainingSupplyQ96X7;

        (uint256 highLhs, uint256 lowLhs) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(remainingSupplyQ96X7, priceQ96);
        assertEq(highLhs, highRhs);
        assertEq(lowLhs, lowRhs);

        assertTrue(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenHighLhs_LT_HighRhs() external pure {
        // it returns false

        // Small demand * remainingMps * Q96 stays below 2^256 → highLhs == 0
        uint256 demandQ96 = 1;
        uint256 remainingMps = 1;
        // supply * price must overflow 2^256 → need both > 2^128
        uint256 remainingSupplyQ96X7 = 1 << 160;
        uint256 priceQ96 = 1 << 160;

        (uint256 highLhs,) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs,) = Math.mul512(remainingSupplyQ96X7, priceQ96);
        assertLt(highLhs, highRhs);

        assertFalse(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenHighLhsEQHighRhs_And_LowLhs_LT_LowRhs() external pure {
        // it returns false

        // demand * remainingMps == supply - 1, price == Q96 → high words match (both 0), lowLhs < lowRhs
        uint256 remainingSupplyQ96X7 = 1000;
        uint256 priceQ96 = FixedPoint96.Q96;
        uint256 remainingMps = 1;
        uint256 demandQ96 = remainingSupplyQ96X7 - 1;

        (uint256 highLhs, uint256 lowLhs) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(remainingSupplyQ96X7, priceQ96);
        assertEq(highLhs, highRhs);
        assertLt(lowLhs, lowRhs);

        assertFalse(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    // --- Fuzz tests: equivalence with requiredDemandAtPrice ---

    function test_WhenDemandGteRequiredDemandAtPrice(
        uint128 _remainingSupplyQ96X7,
        uint128 _priceQ96,
        uint24 _remainingMps
    ) external pure {
        // it returns true

        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint256 remainingMps = bound(_remainingMps, 1, ConstantsLib.MPS);

        uint256 required = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, remainingMps);

        assertTrue(DemandLib.canClearSupplyAtPrice(required, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_EquivalenceWithRequiredDemandAtPrice(
        uint128 _demandQ96,
        uint128 _remainingSupplyQ96X7,
        uint128 _priceQ96,
        uint24 _remainingMps
    ) external pure {
        // it agrees with requiredDemandAtPrice up to ceiling rounding

        uint256 demandQ96 = bound(_demandQ96, 1, type(uint128).max);
        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint256 remainingMps = bound(_remainingMps, 1, ConstantsLib.MPS);

        uint256 required = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, remainingMps);
        bool canClear = DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps);

        if (demandQ96 >= required) {
            assertTrue(canClear);
        }
        if (canClear && demandQ96 < required) {
            assertEq(required - demandQ96, 1);
        }
        if (!canClear) {
            assertLt(demandQ96, required);
        }
    }
}
