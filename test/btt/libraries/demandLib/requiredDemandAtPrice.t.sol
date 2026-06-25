// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ConstantsLib} from '../../../../src/libraries/ConstantsLib.sol';
import {DemandLib} from '../../../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../../../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../../../../src/libraries/ValueX7Lib.sol';
import {BttBase} from 'btt/BttBase.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract RequiredDemandAtPriceWrapper {
    function requiredDemandAtPrice(uint256 _remainingSupplyQ96X7, uint256 _priceQ96, uint256 _remainingMps)
        external
        pure
        returns (uint256)
    {
        return DemandLib.requiredDemandAtPrice(ValueX7.wrap(_remainingSupplyQ96X7), _priceQ96, _remainingMps);
    }
}

contract RequiredDemandAtPriceTest is BttBase {
    RequiredDemandAtPriceWrapper internal wrapper;

    function setUp() external {
        wrapper = new RequiredDemandAtPriceWrapper();
    }

    function test_WhenRemainingMpsIs0(uint256 _remainingSupplyQ96X7, uint256 _priceQ96) external {
        // it reverts

        _remainingSupplyQ96X7 = bound(_remainingSupplyQ96X7, 1, type(uint128).max);
        _priceQ96 = bound(_priceQ96, 1, type(uint128).max);

        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        wrapper.requiredDemandAtPrice(_remainingSupplyQ96X7, _priceQ96, 0);
    }

    function test_WhenPriceIs0(uint256 _remainingSupplyQ96X7, uint24 _remainingMps) external pure {
        // it returns 0

        _remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS));

        uint256 result = DemandLib.requiredDemandAtPrice(ValueX7.wrap(_remainingSupplyQ96X7), 0, _remainingMps);
        assertEq(result, 0);
    }

    function test_WhenSupplyIs0(uint256 _priceQ96, uint24 _remainingMps) external pure {
        // it returns 0

        _remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS));

        uint256 result = DemandLib.requiredDemandAtPrice(ValueX7.wrap(0), _priceQ96, _remainingMps);
        assertEq(result, 0);
    }

    modifier whenSupplyGT0AndPriceGT0() {
        _;
    }

    function test_WhenRemainingMpsIsMPS(uint128 _supplyRaw, uint128 _priceQ96) external pure whenSupplyGT0AndPriceGT0 {
        // it returns remainingSupplyQ96X7 * priceQ96 divUp Q96 * MPS

        uint256 remainingSupplyQ96X7 = bound(_supplyRaw, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);

        uint256 result = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, ConstantsLib.MPS);
        uint256 expected =
            FixedPointMathLib.fullMulDivUp(remainingSupplyQ96X7, priceQ96, FixedPoint96.Q96 * ConstantsLib.MPS);
        assertEq(result, expected);
    }

    function test_WhenRemainingMpsLtMPS(uint128 _supplyRaw, uint128 _priceQ96, uint24 _remainingMps)
        external
        pure
        whenSupplyGT0AndPriceGT0
    {
        // it returns remainingSupplyQ96X7 * priceQ96 divUp Q96 * remainingMps

        uint256 remainingSupplyQ96X7 = bound(_supplyRaw, 1, ConstantsLib.X7_UPPER_BOUND);
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);
        uint24 remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS - 1));

        uint256 result = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, remainingMps);
        uint256 expected =
            FixedPointMathLib.fullMulDivUp(remainingSupplyQ96X7, priceQ96, FixedPoint96.Q96 * remainingMps);
        assertEq(result, expected);
    }

    // --- Rollover ---
    // "On schedule" means totalCleared/totalSupply == cumulativeMps/MPS, giving:
    //     _remainingSupplyQ96X7 = totalSupply * _remainingMps * Q96
    // Substituting into the formula, _remainingMps cancels → demand = totalSupply * _priceQ96

    function test_WhenRemainingSupplyEqualsExpectedSchedule(
        uint64 _totalSupply,
        uint24 _remainingMps,
        uint128 _priceQ96
    ) external pure {
        // it returns totalSupply * priceQ96

        uint256 totalSupply = bound(_totalSupply, 1, type(uint64).max);
        uint24 remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS));
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);

        uint256 remainingSupplyQ96X7 = totalSupply * remainingMps * FixedPoint96.Q96;

        uint256 demand = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, remainingMps);

        assertEq(demand, totalSupply * priceQ96);
    }

    modifier whenRemainingSupplyIsGreaterThanExpectedSchedule() {
        _;
    }

    function test_WhenRemainingSupplyIsGreaterThanExpectedSchedule(
        uint64 _totalSupply,
        uint24 _remainingMps,
        uint128 _priceQ96,
        uint256 _unsoldSupplyQ96X7
    ) external pure whenRemainingSupplyIsGreaterThanExpectedSchedule {
        // it returns totalSupply * priceQ96 + requiredDemandAtPrice(unsoldSupplyQ96X7)

        uint256 totalSupply = bound(_totalSupply, 1, type(uint64).max);
        uint24 remainingMps = uint24(bound(_remainingMps, 1, ConstantsLib.MPS - 1));
        uint256 priceQ96 = bound(_priceQ96, 1, type(uint128).max);

        uint256 onSchedule = totalSupply * remainingMps * FixedPoint96.Q96;
        uint256 unsoldSupplyQ96X7 = bound(_unsoldSupplyQ96X7, 1, onSchedule);
        uint256 remainingSupplyQ96X7 = onSchedule + unsoldSupplyQ96X7;

        uint256 demand = DemandLib.requiredDemandAtPrice(ValueX7.wrap(remainingSupplyQ96X7), priceQ96, remainingMps);

        uint256 unsoldDemand = DemandLib.requiredDemandAtPrice(ValueX7.wrap(unsoldSupplyQ96X7), priceQ96, remainingMps);
        assertEq(demand, totalSupply * priceQ96 + unsoldDemand);
    }
}
