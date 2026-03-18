// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {BttBase} from 'btt/BttBase.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {DemandLib} from 'continuous-clearing-auction/libraries/DemandLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';

contract CanClearSupplyAtPriceTest is BttBase {
    function test_WhenDemandTimesRemainingMps_GT_RemainingSupply(
        uint256 _demandQ96,
        uint256 _remainingSupplyQ96X7,
        uint256 _priceQ96,
        uint24 _remainingMps
    ) external pure {
        // it returns true

        uint256 demandQ96 = bound(_demandQ96, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 remainingMps = bound(_remainingMps, 1, ConstantsLib.MPS);

        (uint256 highLhs, uint256 lowLhs) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(remainingSupplyQ96X7, priceQ96);

        vm.assume(highLhs > highRhs || (highLhs == highRhs && lowLhs > lowRhs));

        assertTrue(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenDemandTimesRemainingMps_EQ_RemainingSupply(uint256 _remainingSupplyQ96X7) external pure {
        // it returns true

        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 0, ConstantsLib.X7_UPPER_BOUND);

        // For simplicitly, assume price is Q96
        uint256 priceQ96 = FixedPoint96.Q96;
        // And that demand == supply
        uint256 demandQ96 = remainingSupplyQ96X7;
        // And that there is 1 mps remaining
        uint256 remainingMps = 1;

        assertTrue(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }

    function test_WhenDemandTimesRemainingMps_LT_RemainingSupply(
        uint256 _demandQ96,
        uint256 _remainingSupplyQ96X7,
        uint256 _priceQ96,
        uint24 _remainingMps
    ) external pure {
        // it returns false

        uint256 demandQ96 = bound(_demandQ96, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 remainingMps = bound(_remainingMps, 1, ConstantsLib.MPS);

        (uint256 highLhs, uint256 lowLhs) = Math.mul512(demandQ96 * remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(remainingSupplyQ96X7, priceQ96);

        vm.assume(highLhs < highRhs || (highLhs == highRhs && lowLhs < lowRhs));

        assertFalse(DemandLib.canClearSupplyAtPrice(demandQ96, remainingSupplyQ96X7, priceQ96, remainingMps));
    }
}
