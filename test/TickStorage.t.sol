// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {Tick} from '../src/libraries/TickLib.sol';
import {Test} from 'forge-std/Test.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing) TickStorage(_tickSpacing) {}

    function getTick(uint256 price) external view returns (Tick memory) {
        return ticks[price];
    }

    function initializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        super._initializeTickIfNeeded(prevPrice, price);
    }

    function updateTick(uint256 price, bool exactIn, uint256 amount) external {
        super._updateTick(price, exactIn, amount);
    }
}

contract TickStorageTest is Test {
    MockTickStorage public tickStorage;
    uint256 public constant TICK_SPACING = 1e18;

    function setUp() public {
        tickStorage = new MockTickStorage(TICK_SPACING);
    }

    function test_initializeTickNoTicks_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
        // First tick in the book has no prev
        assertEq(tick.prev, 0);
        // No other ticks initialized yet, so next is 0
        assertEq(tick.next, 0);
        // First tick is both head and tickUpper
        assertEq(tickStorage.tickUpperPrice(), price);
        assertEq(tickStorage.headTickPrice(), price);
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        uint256 _tickUpperPrice = tickStorage.tickUpperPrice();

        prev = price;
        price = 2e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.prev, 1e18);
        assertEq(tick.next, 0);
        // new tick is not before tickUpper, so tickUpper is not updated
        assertEq(tickStorage.tickUpperPrice(), _tickUpperPrice);
        // Expect head to track the first tick
        assertEq(tickStorage.headTickPrice(), price);
    }

    function test_initializeTickBeforeHead_succeeds() public {
        uint256 prev = 0;
        uint256 price = 2e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(tickStorage.tickUpperPrice(), price);

        prev = 0;
        price = 1e18;
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickUpperUpdated(1e18);
        emit ITickStorage.TickInitialized(1e18);
        tickStorage.initializeTickIfNeeded(prev, price);

        Tick memory tick = tickStorage.getTick(price);
        // Assert that this is now the head tick
        assertEq(tick.prev, 0);
        // And the first tick we added is next
        assertEq(tick.next, 2e18);
        // Assert that this is now the head tick
        assertEq(tickStorage.headTickPrice(), price);
        // Assert that the tickUpper is updated to this tick
        assertEq(tickStorage.tickUpperPrice(), price);
    }

    function test_initializeTickReturnsExistingTickAtHead_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        tickStorage.initializeTickIfNeeded(0, price);
    }

    function test_initializeTickReturnsExistingTick_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        tickStorage.initializeTickIfNeeded(price, 2e18);
    }

    function test_initializeTickWithWrongPrice_reverts() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        prev = price;
        price = 0;
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(prev, price);
    }

    function test_initializeTickWithWrongPriceBetweenTicks_reverts() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        tickStorage.initializeTickIfNeeded(price, 2e18);

        // Wrong price, between ticks must be increasing
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(1e18, 3e18);
    }

    function test_initializeTickBeforeHeadWithWrongPrice_reverts() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        prev = 0;
        // Wrong price, head must be less than all other ticks
        price = 2e18;
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(prev, price);
    }

    function test_updateTickNewTickAtHead_succeeds() public {
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(0, price);

        tickStorage.updateTick(price, true, 1e18);
        tickStorage.updateTick(price, false, 1e18);
        assertEq(tickStorage.getTick(price).demand.currencyDemand, 1e18);
        assertEq(tickStorage.getTick(price).demand.tokenDemand, 1e18);
    }

    function test_getLowerTickForPriceAtPrice_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        Tick memory tick = tickStorage.getLowerTickForPrice(1e18);
        assertEq(tick.prev, 0);
        assertEq(tick.next, 0);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getLowerTickForPriceAboveTickReturnsHighestTick_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        // Price is above the highest tick, so the highest tick is returned
        Tick memory tick = tickStorage.getLowerTickForPrice(2e18);
        assertEq(tick.prev, 0);
        assertEq(tick.next, 0);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getLowerTickForPriceBelowTick_succeeds() public {
        uint256 prev = 0;
        uint256 price = 1e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        prev = price;
        price = 2e18;
        tickStorage.initializeTickIfNeeded(prev, price);

        Tick memory tick = tickStorage.getLowerTickForPrice(1.5e18);
        assertEq(tick.prev, 0);
        assertEq(tick.next, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);

        price = 4e18;
        tickStorage.initializeTickIfNeeded(price, price);

        tick = tickStorage.getLowerTickForPrice(3e18);
        assertEq(tick.prev, 1e18);
        assertEq(tick.next, 0);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }
}
