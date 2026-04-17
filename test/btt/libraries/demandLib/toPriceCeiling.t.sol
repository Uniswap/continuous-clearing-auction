// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {DemandLib} from 'continuous-clearing-auction/libraries/DemandLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract ToPriceCeilingTest is BttBase {
    function test_WhenDemandIs0(uint256 _remainingSupplyQ96X7, uint24 _remainingMps) external pure {
        // it returns 0

        _remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, ConstantsLib.X7_UPPER_BOUND);
        _remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS));

        assertEq(DemandLib.toPriceCeiling(0, _remainingSupplyQ96X7, _remainingMps), 0);
    }

    function test_WhenDemandGT0AndSupplyGT0(uint128 _demandQ96, uint128 _remainingSupplyQ96X7, uint24 _remainingMps)
        external
        pure
    {
        // it returns demand * remainingMps * Q96 divUp supply

        uint256 demandQ96 = bound(_demandQ96, 1, type(uint128).max);
        uint256 remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        uint256 remainingMps = bound(_remainingMps, 1, ConstantsLib.MPS);

        uint256 result = DemandLib.toPriceCeiling(demandQ96, remainingSupplyQ96X7, remainingMps);
        uint256 expected =
            FixedPointMathLib.fullMulDivUp(demandQ96 * remainingMps, FixedPoint96.Q96, remainingSupplyQ96X7);
        assertEq(result, expected);
    }
}
