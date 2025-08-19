// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Tick, TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';

import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing, uint256 _floorPrice) TickStorage(_tickSpacing, _floorPrice) {}

    function initializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        super._initializeTickIfNeeded(prevPrice, price);
    }

    function updateTick(uint256 price, bool exactIn, uint256 amount) external {
        super._updateTick(price, exactIn, amount);
    }
}

contract TickStorageTest is Test {
    MockTickStorage public tickStorage;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant FLOOR_PRICE = 100 << FixedPoint96.RESOLUTION;

    function setUp() public {
        tickStorage = new MockTickStorage(TICK_SPACING, FLOOR_PRICE);
    }

    /// Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return ((FLOOR_PRICE >> FixedPoint96.RESOLUTION) + (tickNumber - 1) * TICK_SPACING) << FixedPoint96.RESOLUTION;
    }

    function test_initializeTick_succeeds() public {
        uint256 prev = FLOOR_PRICE;
        // 2e18 << FixedPoint96.RESOLUTION
        uint256 price = tickNumberToPriceX96(2);
        tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
        // Assert there is no next tick (type(uint256).max)
        assertEq(tick.next, type(uint256).max);
        // Assert the tickUpper is unchanged
        assertEq(tickStorage.tickUpperPrice(), FLOOR_PRICE);
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint256 _tickUpperPrice = tickStorage.tickUpperPrice();
        assertEq(_tickUpperPrice, FLOOR_PRICE);

        uint256 price = tickNumberToPriceX96(2);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint256).max);
        // new tick is not before tickUpper, so tickUpper is not updated
        assertEq(tickStorage.tickUpperPrice(), _tickUpperPrice);
    }

    function test_initializeTickSetsNext_succeeds() public {
        uint256 prev = FLOOR_PRICE;
        uint256 price = tickNumberToPriceX96(2);
        tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint256).max);

        tickStorage.initializeTickIfNeeded(price, tickNumberToPriceX96(3));
        tick = tickStorage.getTick(tickNumberToPriceX96(3));
        assertEq(tick.next, type(uint256).max);

        tick = tickStorage.getTick(tickNumberToPriceX96(2));
        assertEq(tick.next, tickNumberToPriceX96(3));
    }

    function test_initializeTickWithWrongPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, 0);
    }

    function test_initializeTickAtFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, FLOOR_PRICE);
    }

    // The tick at 0 id should never be initialized, thus its next value is 0, which should cause a revert
    function test_initializeTickWithZeroPrev_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(0, tickNumberToPriceX96(2));
    }

    function test_initializeTickWithWrongPriceBetweenTicks_reverts() public {
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, tickNumberToPriceX96(2));

        // Wrong price, between ticks must be increasing
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, tickNumberToPriceX96(3));
    }
}
