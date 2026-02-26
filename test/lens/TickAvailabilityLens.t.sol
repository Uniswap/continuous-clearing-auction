// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {TickAvailability, TickAvailabilityLens} from '../../src/lens/TickAvailabilityLens.sol';
import {AuctionUnitTest} from '../unit/AuctionUnitTest.sol';

contract TickAvailabilityLensTest is AuctionUnitTest {
    TickAvailabilityLens public lens;

    function setUp() public {
        setUpMockAuction();
        lens = new TickAvailabilityLens();
    }

    /// @notice When there are no bids, only the floor tick exists with full supply available
    function test_noBids() public view {
        TickAvailability[] memory result =
            lens.getTickAvailability(IContinuousClearingAuction(address(mockAuction)));

        // Only the floor tick should exist
        assertEq(result.length, 1);
        assertEq(result[0].price, params.floorPrice);
        assertEq(result[0].currencyDemandQ96, 0);
        assertEq(result[0].cumulativeDemandAboveQ96, 0);
        assertEq(result[0].tokensAvailable, TOTAL_SUPPLY);
    }

    /// @notice Single tick with demand above floor — verify tokensAvailable at both ticks
    function test_singleTickWithDemand() public {
        uint256 tickPrice = params.floorPrice + params.tickSpacing;
        // Demand stored as Q96-scaled currency: demandQ96 = tokenAmount * priceQ96
        // This matches production format: bidAmount << 96 (with MPS/mpsRemaining ≈ 1)
        uint256 demandQ96 = 100e18 * tickPrice;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tickPrice);
        mockAuction.uncheckedUpdateTickDemand(tickPrice, demandQ96);
        mockAuction.uncheckedSetSumDemandAboveClearing(demandQ96);

        TickAvailability[] memory result =
            lens.getTickAvailability(IContinuousClearingAuction(address(mockAuction)));

        assertEq(result.length, 2);

        // Floor tick (lowest) — demand above includes tickPrice's demand
        assertEq(result[0].price, params.floorPrice);
        assertEq(result[0].cumulativeDemandAboveQ96, demandQ96);
        // tokensAvailable at floor = totalSupply - demandQ96 / floorPrice
        uint256 tokensConsumedAtFloor = demandQ96 / params.floorPrice;
        assertEq(result[0].tokensAvailable, TOTAL_SUPPLY - tokensConsumedAtFloor);

        // Higher tick — no demand above it
        assertEq(result[1].price, tickPrice);
        assertEq(result[1].currencyDemandQ96, demandQ96);
        assertEq(result[1].cumulativeDemandAboveQ96, 0);
        assertEq(result[1].tokensAvailable, TOTAL_SUPPLY);
    }

    /// @notice Multiple ticks with demand — verify cumulative demand flows correctly top-down
    function test_multipleTicksWithDemand() public {
        uint256 tick1 = params.floorPrice + params.tickSpacing;
        uint256 tick2 = params.floorPrice + 2 * params.tickSpacing;
        uint256 tick3 = params.floorPrice + 3 * params.tickSpacing;

        uint256 demand1Q96 = 50e18 * tick1;
        uint256 demand2Q96 = 30e18 * tick2;
        uint256 demand3Q96 = 20e18 * tick3;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tick1);
        mockAuction.uncheckedInitializeTickIfNeeded(tick1, tick2);
        mockAuction.uncheckedInitializeTickIfNeeded(tick2, tick3);

        mockAuction.uncheckedUpdateTickDemand(tick1, demand1Q96);
        mockAuction.uncheckedUpdateTickDemand(tick2, demand2Q96);
        mockAuction.uncheckedUpdateTickDemand(tick3, demand3Q96);
        mockAuction.uncheckedSetSumDemandAboveClearing(demand1Q96 + demand2Q96 + demand3Q96);

        TickAvailability[] memory result =
            lens.getTickAvailability(IContinuousClearingAuction(address(mockAuction)));

        assertEq(result.length, 4); // floor + 3 ticks

        // Tick3 (highest) — no demand above
        assertEq(result[3].price, tick3);
        assertEq(result[3].cumulativeDemandAboveQ96, 0);
        assertEq(result[3].tokensAvailable, TOTAL_SUPPLY);

        // Tick2 — demand above = demand3
        assertEq(result[2].price, tick2);
        assertEq(result[2].cumulativeDemandAboveQ96, demand3Q96);

        // Tick1 — demand above = demand2 + demand3
        assertEq(result[1].price, tick1);
        assertEq(result[1].cumulativeDemandAboveQ96, demand2Q96 + demand3Q96);

        // Floor — demand above = demand1 + demand2 + demand3
        assertEq(result[0].price, params.floorPrice);
        assertEq(result[0].cumulativeDemandAboveQ96, demand1Q96 + demand2Q96 + demand3Q96);
    }

    // ========== getTickAvailabilityFull tests ==========

    /// @notice Initialize ticks at spacing 1, 3, 5 (skip 2, 4). Verify full function returns
    /// entries for all 5 positions with correct cumulative demand at uninitialized ticks.
    function test_fullAvailability_fillsGaps() public {
        uint256 tick1 = params.floorPrice + params.tickSpacing; // spacing 1
        uint256 tick3 = params.floorPrice + 3 * params.tickSpacing; // spacing 3
        uint256 tick5 = params.floorPrice + 5 * params.tickSpacing; // spacing 5

        uint256 demand1Q96 = 50e18 * tick1;
        uint256 demand3Q96 = 30e18 * tick3;
        uint256 demand5Q96 = 20e18 * tick5;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tick1);
        mockAuction.uncheckedInitializeTickIfNeeded(tick1, tick3);
        mockAuction.uncheckedInitializeTickIfNeeded(tick3, tick5);

        mockAuction.uncheckedUpdateTickDemand(tick1, demand1Q96);
        mockAuction.uncheckedUpdateTickDemand(tick3, demand3Q96);
        mockAuction.uncheckedUpdateTickDemand(tick5, demand5Q96);

        (TickAvailability[] memory result, uint256 nextPrice) = lens.getTickAvailabilityFull(
            IContinuousClearingAuction(address(mockAuction)), params.floorPrice, 100
        );

        // floor + tick1 + tick2(uninit) + tick3 + tick4(uninit) + tick5 = 6 entries
        assertEq(result.length, 6);
        assertEq(nextPrice, 0); // all done

        // Floor: cumulative above = demand1 + demand3 + demand5
        assertEq(result[0].price, params.floorPrice);
        assertEq(result[0].cumulativeDemandAboveQ96, demand1Q96 + demand3Q96 + demand5Q96);
        assertEq(result[0].currencyDemandQ96, 0);

        // Tick1: cumulative above = demand3 + demand5
        assertEq(result[1].price, tick1);
        assertEq(result[1].cumulativeDemandAboveQ96, demand3Q96 + demand5Q96);
        assertEq(result[1].currencyDemandQ96, demand1Q96);

        // Tick2 (uninitialized): same cumulative as tick1 (inherits from initialized tick below)
        uint256 tick2 = params.floorPrice + 2 * params.tickSpacing;
        assertEq(result[2].price, tick2);
        assertEq(result[2].cumulativeDemandAboveQ96, demand3Q96 + demand5Q96);
        assertEq(result[2].currencyDemandQ96, 0); // no demand at uninitialized tick

        // Tick3: cumulative above = demand5
        assertEq(result[3].price, tick3);
        assertEq(result[3].cumulativeDemandAboveQ96, demand5Q96);
        assertEq(result[3].currencyDemandQ96, demand3Q96);

        // Tick4 (uninitialized): same cumulative as tick3
        uint256 tick4 = params.floorPrice + 4 * params.tickSpacing;
        assertEq(result[4].price, tick4);
        assertEq(result[4].cumulativeDemandAboveQ96, demand5Q96);
        assertEq(result[4].currencyDemandQ96, 0);

        // Tick5: cumulative above = 0
        assertEq(result[5].price, tick5);
        assertEq(result[5].cumulativeDemandAboveQ96, 0);
        assertEq(result[5].currencyDemandQ96, demand5Q96);
    }

    /// @notice Request small limit, verify nextPrice, call again, verify continuity
    function test_fullAvailability_pagination() public {
        uint256 tick1 = params.floorPrice + params.tickSpacing;
        uint256 tick3 = params.floorPrice + 3 * params.tickSpacing;
        uint256 tick5 = params.floorPrice + 5 * params.tickSpacing;

        uint256 demand1Q96 = 50e18 * tick1;
        uint256 demand3Q96 = 30e18 * tick3;
        uint256 demand5Q96 = 20e18 * tick5;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tick1);
        mockAuction.uncheckedInitializeTickIfNeeded(tick1, tick3);
        mockAuction.uncheckedInitializeTickIfNeeded(tick3, tick5);

        mockAuction.uncheckedUpdateTickDemand(tick1, demand1Q96);
        mockAuction.uncheckedUpdateTickDemand(tick3, demand3Q96);
        mockAuction.uncheckedUpdateTickDemand(tick5, demand5Q96);

        // Page 1: limit 3 — should get floor, tick1, tick2
        (TickAvailability[] memory page1, uint256 nextPrice1) = lens.getTickAvailabilityFull(
            IContinuousClearingAuction(address(mockAuction)), params.floorPrice, 3
        );
        assertEq(page1.length, 3);
        assertEq(page1[0].price, params.floorPrice);
        assertEq(page1[1].price, tick1);
        assertEq(page1[2].price, params.floorPrice + 2 * params.tickSpacing);
        assertEq(nextPrice1, params.floorPrice + 3 * params.tickSpacing); // tick3

        // Page 2: from nextPrice1, limit 3 — should get tick3, tick4, tick5
        (TickAvailability[] memory page2, uint256 nextPrice2) = lens.getTickAvailabilityFull(
            IContinuousClearingAuction(address(mockAuction)), nextPrice1, 3
        );
        assertEq(page2.length, 3);
        assertEq(page2[0].price, tick3);
        assertEq(page2[1].price, params.floorPrice + 4 * params.tickSpacing);
        assertEq(page2[2].price, tick5);
        assertEq(nextPrice2, 0); // done

        // Verify continuity: page1 last and page2 first are consecutive
        assertEq(page2[0].price - page1[2].price, params.tickSpacing);
    }

    /// @notice Verify result stops at highest initialized tick, nextPrice == 0
    function test_fullAvailability_stopsAtHighestTick() public {
        uint256 tick2 = params.floorPrice + 2 * params.tickSpacing;

        uint256 demand2Q96 = 100e18 * tick2;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tick2);
        mockAuction.uncheckedUpdateTickDemand(tick2, demand2Q96);

        (TickAvailability[] memory result, uint256 nextPrice) = lens.getTickAvailabilityFull(
            IContinuousClearingAuction(address(mockAuction)), params.floorPrice, 10000
        );

        // floor + tick1(uninit) + tick2 = 3
        assertEq(result.length, 3);
        assertEq(result[2].price, tick2);
        assertEq(nextPrice, 0);

        // The highest tick has 0 cumulative demand above
        assertEq(result[2].cumulativeDemandAboveQ96, 0);
        assertEq(result[2].tokensAvailable, TOTAL_SUPPLY);
    }

    /// @notice Unaligned fromPrice snaps down correctly
    function test_fullAvailability_snapsFromPrice() public {
        uint256 tick2 = params.floorPrice + 2 * params.tickSpacing;
        uint256 tick4 = params.floorPrice + 4 * params.tickSpacing;

        uint256 demand2Q96 = 50e18 * tick2;
        uint256 demand4Q96 = 50e18 * tick4;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tick2);
        mockAuction.uncheckedInitializeTickIfNeeded(tick2, tick4);
        mockAuction.uncheckedUpdateTickDemand(tick2, demand2Q96);
        mockAuction.uncheckedUpdateTickDemand(tick4, demand4Q96);

        // Pass a fromPrice that's not aligned — halfway between tick2 and tick3
        uint256 unaligned = tick2 + params.tickSpacing / 2;

        (TickAvailability[] memory result, uint256 nextPrice) = lens.getTickAvailabilityFull(
            IContinuousClearingAuction(address(mockAuction)), unaligned, 100
        );

        // Should snap down to tick2, giving us tick2, tick3(uninit), tick4
        assertEq(result.length, 3);
        assertEq(result[0].price, tick2);
        assertEq(result[1].price, params.floorPrice + 3 * params.tickSpacing);
        assertEq(result[2].price, tick4);
        assertEq(nextPrice, 0);
    }

    /// @notice Enough demand above a tick that tokensAvailable clamps to 0
    function test_fullyConsumed() public {
        uint256 tickPrice = params.floorPrice + params.tickSpacing;
        // Demand enough to consume all tokens at the floor price:
        // tokensConsumed = demandQ96 / floorPrice >= TOTAL_SUPPLY
        // demandQ96 >= TOTAL_SUPPLY * floorPrice
        uint256 demandQ96 = uint256(TOTAL_SUPPLY) * params.floorPrice;
        // Add extra to ensure full consumption
        demandQ96 += params.floorPrice;

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tickPrice);
        mockAuction.uncheckedUpdateTickDemand(tickPrice, demandQ96);
        mockAuction.uncheckedSetSumDemandAboveClearing(demandQ96);

        TickAvailability[] memory result =
            lens.getTickAvailability(IContinuousClearingAuction(address(mockAuction)));

        assertEq(result.length, 2);

        // Floor tick should be fully consumed (clamped to 0)
        assertEq(result[0].price, params.floorPrice);
        assertEq(result[0].tokensAvailable, 0);

        // Higher tick — no demand above it, full supply available
        assertEq(result[1].price, tickPrice);
        assertEq(result[1].tokensAvailable, TOTAL_SUPPLY);
    }
}
