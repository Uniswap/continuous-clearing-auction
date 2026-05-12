// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {Tick} from '../../src/interfaces/ITickStorage.sol';
import {TickDataLens, TickWithData} from '../../src/lens/TickDataLens.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionUnitTest} from '../unit/AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract TickDataLensTest is AuctionUnitTest {
    using FixedPointMathLib for *;

    TickDataLens public lens;

    function setUp() public {
        setUpMockAuction();
        lens = new TickDataLens();
    }

    function test_getInitializedTickData_returnsEmptyWhenNoTicksAboveClearing() public view {
        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 0);
    }

    function test_getInitializedTickData_singleTick() public {
        uint256 price = params.floorPrice + params.tickSpacing;
        uint256 demand = 1e18 << FixedPoint96.RESOLUTION;

        _initializeTick(price, demand);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 1);
        assertEq(ticks[0].priceQ96, price);
        assertEq(ticks[0].currencyDemandQ96, demand);

        uint256 expectedRequired = _expectedRequiredDemand(price);
        assertEq(ticks[0].requiredCurrencyDemandQ96, expectedRequired);

        uint256 expectedCurrencyRequired = _expectedCurrencyRequired(expectedRequired, demand);
        assertEq(ticks[0].currencyRequiredQ96, expectedCurrencyRequired);
    }

    function test_getInitializedTickData_multipleTicks() public {
        uint256 price1 = params.floorPrice + params.tickSpacing;
        uint256 price2 = params.floorPrice + 2 * params.tickSpacing;
        uint256 demand1 = 1e18 << FixedPoint96.RESOLUTION;
        uint256 demand2 = 2e18 << FixedPoint96.RESOLUTION;
        uint256 totalDemand = demand1 + demand2;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, price1);
        mockAuction.uncheckedInitializeTickIfNeeded(price1, price2);
        mockAuction.uncheckedUpdateTickDemand(price1, demand1);
        mockAuction.uncheckedUpdateTickDemand(price2, demand2);
        mockAuction.uncheckedSetNextActiveTickPrice(price1);
        mockAuction.uncheckedSetSumDemandAboveClearing(totalDemand);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 2);

        // First tick: sumDemand includes demand at both ticks
        assertEq(ticks[0].priceQ96, price1);
        assertEq(ticks[0].currencyDemandQ96, demand1);
        uint256 required1 = _expectedRequiredDemand(price1);
        assertEq(ticks[0].requiredCurrencyDemandQ96, required1);
        assertEq(ticks[0].currencyRequiredQ96, _expectedCurrencyRequired(required1, totalDemand));

        // Second tick: sumDemand has been reduced by demand1
        assertEq(ticks[1].priceQ96, price2);
        assertEq(ticks[1].currencyDemandQ96, demand2);
        uint256 required2 = _expectedRequiredDemand(price2);
        assertEq(ticks[1].requiredCurrencyDemandQ96, required2);
        assertEq(ticks[1].currencyRequiredQ96, _expectedCurrencyRequired(required2, demand2));
    }

    function test_getInitializedTickData_currencyRequiredIsZeroWhenDemandExceedsRequired() public {
        uint256 price = params.floorPrice + params.tickSpacing;
        uint256 requiredDemand = _expectedRequiredDemand(price);
        uint256 demand = requiredDemand * 2;

        _initializeTick(price, demand);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 1);
        assertEq(ticks[0].currencyRequiredQ96, 0);
    }

    function test_getInitializedTickData_scalesByRemainingMps() public {
        // Advance 1 block to create a checkpoint with non-zero cumulativeMps
        vm.roll(block.number + 1);
        mockAuction.checkpoint();

        uint256 price = params.floorPrice + params.tickSpacing;
        uint256 demand = 1e18 << FixedPoint96.RESOLUTION;

        _initializeTick(price, demand);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 1);

        // After 1 block at STANDARD_MPS_1_PERCENT, cumulativeMps = STANDARD_MPS_1_PERCENT
        uint24 expectedRemainingMps = ConstantsLib.MPS - STANDARD_MPS_1_PERCENT;
        uint256 expectedRequiredDemand = _expectedRequiredDemand(price);
        assertGt(expectedRequiredDemand, uint256(TOTAL_SUPPLY) * price);

        uint256 shortfall = expectedRequiredDemand.saturatingSub(demand);
        uint256 expectedCurrencyRequired = shortfall.fullMulDivUp(expectedRemainingMps, ConstantsLib.MPS);
        assertEq(ticks[0].requiredCurrencyDemandQ96, expectedRequiredDemand);
        assertEq(ticks[0].currencyRequiredQ96, expectedCurrencyRequired);
    }

    function test_getInitializedTickData_afterAuctionEnds() public {
        uint256 price = params.floorPrice + params.tickSpacing;
        uint256 demand = 1e18 << FixedPoint96.RESOLUTION;

        _initializeTick(price, demand);

        // Roll past end of auction so cumulativeMps == MPS and remainingMps == 0
        vm.roll(block.number + AUCTION_DURATION + 1);
        mockAuction.checkpoint();

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 1);
        assertEq(ticks[0].priceQ96, price);
        assertEq(ticks[0].currencyDemandQ96, demand);
        assertEq(ticks[0].requiredCurrencyDemandQ96, 0);
        // With remainingMps == 0, currencyRequired scales to 0
        assertEq(ticks[0].currencyRequiredQ96, 0);
    }

    function test_getInitializedTickData_ticksReturnedInOrder() public {
        uint256 price1 = params.floorPrice + params.tickSpacing;
        uint256 price2 = params.floorPrice + 2 * params.tickSpacing;
        uint256 price3 = params.floorPrice + 3 * params.tickSpacing;
        uint256 demandPerTick = 1e18 << FixedPoint96.RESOLUTION;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, price1);
        mockAuction.uncheckedInitializeTickIfNeeded(price1, price2);
        mockAuction.uncheckedInitializeTickIfNeeded(price2, price3);
        mockAuction.uncheckedUpdateTickDemand(price1, demandPerTick);
        mockAuction.uncheckedUpdateTickDemand(price2, demandPerTick);
        mockAuction.uncheckedUpdateTickDemand(price3, demandPerTick);
        mockAuction.uncheckedSetNextActiveTickPrice(price1);
        mockAuction.uncheckedSetSumDemandAboveClearing(demandPerTick * 3);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 3);
        assertEq(ticks[0].priceQ96, price1);
        assertEq(ticks[1].priceQ96, price2);
        assertEq(ticks[2].priceQ96, price3);
        // Prices are strictly increasing
        assertLt(ticks[0].priceQ96, ticks[1].priceQ96);
        assertLt(ticks[1].priceQ96, ticks[2].priceQ96);
    }

    function test_getInitializedTickData_requiredCurrencyDemandIncreases() public {
        uint256 price1 = params.floorPrice + params.tickSpacing;
        uint256 price2 = params.floorPrice + 2 * params.tickSpacing;
        uint256 demandPerTick = 1e18 << FixedPoint96.RESOLUTION;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, price1);
        mockAuction.uncheckedInitializeTickIfNeeded(price1, price2);
        mockAuction.uncheckedUpdateTickDemand(price1, demandPerTick);
        mockAuction.uncheckedUpdateTickDemand(price2, demandPerTick);
        mockAuction.uncheckedSetNextActiveTickPrice(price1);
        mockAuction.uncheckedSetSumDemandAboveClearing(demandPerTick * 2);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, 2);
        assertLt(ticks[0].requiredCurrencyDemandQ96, ticks[1].requiredCurrencyDemandQ96);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_getInitializedTickData_fuzz(uint256 numTicks) public {
        numTicks = bound(numTicks, 1, lens.MAX_BUFFER_SIZE());

        (uint256[] memory prices, uint256[] memory demands, uint256 totalDemand) = _initializeTicks(numTicks);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, numTicks);

        uint256 runningDemand = totalDemand;
        for (uint256 i = 0; i < numTicks; i++) {
            uint256 required = _expectedRequiredDemand(prices[i]);
            assertEq(ticks[i].priceQ96, prices[i]);
            assertEq(ticks[i].currencyDemandQ96, demands[i]);
            assertEq(ticks[i].requiredCurrencyDemandQ96, required);
            assertEq(ticks[i].currencyRequiredQ96, _expectedCurrencyRequired(required, runningDemand));
            runningDemand -= demands[i];
        }
    }

    function test_getInitializedTickData_MaxBufferSize() public {
        uint256 numTicks = lens.MAX_BUFFER_SIZE();
        (uint256[] memory prices, uint256[] memory demands, uint256 totalDemand) = _initializeTicks(numTicks);

        TickWithData[] memory ticks = lens.getInitializedTickData(IContinuousClearingAuction(address(mockAuction)));

        assertEq(ticks.length, numTicks);

        uint256 runningDemand = totalDemand;
        for (uint256 i = 0; i < numTicks; i++) {
            uint256 required = _expectedRequiredDemand(prices[i]);
            assertEq(ticks[i].priceQ96, prices[i]);
            assertEq(ticks[i].currencyDemandQ96, demands[i]);
            assertEq(ticks[i].requiredCurrencyDemandQ96, required);
            assertEq(ticks[i].currencyRequiredQ96, _expectedCurrencyRequired(required, runningDemand));
            runningDemand -= demands[i];
        }
    }

    // ============================================
    // Helpers
    // ============================================

    function _initializeTick(uint256 price, uint256 demand) internal {
        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, price);
        mockAuction.uncheckedUpdateTickDemand(price, demand);
        mockAuction.uncheckedSetNextActiveTickPrice(price);
        mockAuction.uncheckedSetSumDemandAboveClearing(demand);
    }

    function _initializeTicks(uint256 numTicks)
        internal
        returns (uint256[] memory prices, uint256[] memory demands, uint256 totalDemand)
    {
        prices = new uint256[](numTicks);
        demands = new uint256[](numTicks);

        uint256 prevPrice = params.floorPrice;
        for (uint256 i = 0; i < numTicks; i++) {
            prices[i] = params.floorPrice + (i + 1) * params.tickSpacing;
            demands[i] = (i + 1) * (1e18 << FixedPoint96.RESOLUTION);
            totalDemand += demands[i];
            mockAuction.uncheckedInitializeTickIfNeeded(prevPrice, prices[i]);
            mockAuction.uncheckedUpdateTickDemand(prices[i], demands[i]);
            prevPrice = prices[i];
        }
        mockAuction.uncheckedSetNextActiveTickPrice(prices[0]);
        mockAuction.uncheckedSetSumDemandAboveClearing(totalDemand);
    }

    function _expectedRequiredDemand(uint256 price) internal view returns (uint256) {
        return mockAuction.requiredDemandQ96(price);
    }

    function _expectedCurrencyRequired(uint256 requiredDemand, uint256 runningDemand) internal view returns (uint256) {
        uint24 remainingMps = ConstantsLib.MPS - mockAuction.latestCheckpoint().cumulativeMps;
        return requiredDemand.saturatingSub(runningDemand).fullMulDivUp(remainingMps, ConstantsLib.MPS);
    }
}
