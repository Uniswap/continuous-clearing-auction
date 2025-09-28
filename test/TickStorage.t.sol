// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Tick, TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {Test} from 'forge-std/Test.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing, uint256 _floorPrice) TickStorage(_tickSpacing, _floorPrice) {}

    /// @notice Set the nextActiveTickPrice, only for testing
    function setNextActiveTickPrice(uint256 price) external {
        $nextActiveTickPrice = price;
    }

    function initializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        super._initializeTickIfNeeded(prevPrice, price);
    }

    function updateTick(uint256 price, bool exactIn, uint128 amount) external {
        super._updateTick(price, exactIn, amount);
    }
}

contract TickStorageTest is Test {
    MockTickStorage public tickStorage;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant FLOOR_PRICE = 100e6; // 100 in X96 format

    function setUp() public {
        tickStorage = new MockTickStorage(TICK_SPACING, FLOOR_PRICE);
    }

    /// Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return FLOOR_PRICE + (tickNumber - 1) * TICK_SPACING;
    }

    function test_tickStorage_canBeConstructed_fuzz(uint256 tickSpacing, uint256 floorPrice) public {
        MockTickStorage _tickStorage;
        if (tickSpacing == 0) {
            vm.expectRevert(ITickStorage.TickSpacingIsZero.selector);
            _tickStorage = new MockTickStorage(tickSpacing, floorPrice);
        } else if (floorPrice % tickSpacing != 0) {
            vm.expectRevert(ITickStorage.TickPriceNotAtBoundary.selector);
            _tickStorage = new MockTickStorage(tickSpacing, floorPrice);
        } else {
            _tickStorage = new MockTickStorage(tickSpacing, floorPrice);
            assertEq(_tickStorage.floorPrice(), floorPrice);
            assertEq(_tickStorage.tickSpacing(), tickSpacing);
            assertEq(_tickStorage.nextActiveTickPrice(), floorPrice);
            assertEq(_tickStorage.getTick(floorPrice).next, type(uint256).max);
        }
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
        // Assert the nextActiveTick is unchanged
        assertEq(tickStorage.nextActiveTickPrice(), FLOOR_PRICE);
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint256 _nextActiveTickPrice = tickStorage.nextActiveTickPrice();
        assertEq(_nextActiveTickPrice, FLOOR_PRICE);

        uint256 price = tickNumberToPriceX96(2);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint256).max);
        // new tick is not before nextActiveTick, so nextActiveTick is not updated
        assertEq(tickStorage.nextActiveTickPrice(), _nextActiveTickPrice);
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

    function test_initializeTickSetsNextActiveTickPrice_whenNextActiveTickPriceIsMax_succeeds() public {
        uint256 price = tickNumberToPriceX96(2);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint256).max);

        // Set nextActiveTickPrice to MAX_TICK_PRICE
        tickStorage.setNextActiveTickPrice(type(uint256).max);
        assertEq(tickStorage.nextActiveTickPrice(), type(uint256).max);

        // Initializing a tick above the highest tick in the book should set nextActiveTickPrice to the new tick
        tickStorage.initializeTickIfNeeded(price, tickNumberToPriceX96(3));
        assertEq(tickStorage.nextActiveTickPrice(), tickNumberToPriceX96(3));
    }

    function test_initializeTickUpdatesNextActiveTickPrice_succeeds() public {
        // Set nextActiveTickPrice to a high value
        uint256 maxTickPrice = type(uint256).max;
        vm.store(address(tickStorage), bytes32(uint256(1)), bytes32(maxTickPrice));

        // When we call initializeTickIfNeeded, the new tick should update nextActiveTickPrice
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, 200e6);
        assertEq(tickStorage.nextActiveTickPrice(), 200e6);
    }

    function test_initializeTickWithWrongPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, 0);
    }

    function test_initializeTickAtFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
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

    function test_initializeTickIfNeeded_withNextIdLessThanId_reverts() public {
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, 2e18);

        // Then try to initialize a tick at price 3 with prevId=1, but nextId=2 is less than id=3
        // This should revert because nextId < id
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(FLOOR_PRICE, 3e18);
    }

    function test_initializeTickIfNeeded_withPrevIdGreaterThanId_reverts() public {
        // Try to initialize a tick at price 1 with prevId=2, but prevId > id
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(2, 1e18);
    }
}
