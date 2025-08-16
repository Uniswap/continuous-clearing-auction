// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {Tick} from '../src/libraries/TickLib.sol';
import {Test} from 'forge-std/Test.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing) TickStorage(_tickSpacing) {}

    function getTick(uint128 id) external view returns (Tick memory) {
        return ticks[id];
    }

    function initializeTickIfNeeded(uint128 prev, uint256 price) external returns (uint128) {
        return super._initializeTickIfNeeded(prev, price);
    }

    function updateTick(uint128 id, bool exactIn, uint256 amount) external {
        super._updateTick(id, exactIn, amount);
    }
}

contract TickStorageTest is Test {
    MockTickStorage public tickStorage;
    uint256 public constant TICK_SPACING = 1e18;

    function setUp() public {
        tickStorage = new MockTickStorage(TICK_SPACING);
    }

    function test_initializeTickNoTicks_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);
        Tick memory tick = tickStorage.getTick(id);
        assertEq(tick.price, price);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
        // First tick in the book has no prev
        assertEq(tick.prev, 0);
        // No other ticks initialized yet, so next is 0
        assertEq(tick.next, 0);
        // First tick is both head and tickUpper
        assertEq(tickStorage.tickUpperId(), 1);
        assertEq(tickStorage.headTickId(), 1);
        assertEq(tickStorage.lastInitializedTickId(), 1);
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);
        uint256 _tickUpperId = tickStorage.tickUpperId();

        prev = id;
        price = 2e18;
        id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 2);
        Tick memory tick = tickStorage.getTick(id);
        assertEq(tick.price, price);
        assertEq(tick.prev, 1);
        assertEq(tick.next, 0);
        // new tick is not before tickUpper, so tickUpper is not updated
        assertEq(tickStorage.tickUpperId(), _tickUpperId);
        // Expect head to track the first tick
        assertEq(tickStorage.headTickId(), 1);
        assertEq(tickStorage.lastInitializedTickId(), 2);
    }

    function test_initializeTickBeforeHead_succeeds() public {
        uint128 prev = 0;
        uint256 price = 2e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);
        assertEq(tickStorage.tickUpperId(), 1);

        prev = 0;
        price = 1e18;
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickUpperUpdated(2);
        id = tickStorage.initializeTickIfNeeded(prev, price);

        assertEq(id, 2);
        Tick memory tick = tickStorage.getTick(id);
        assertEq(tick.price, 1e18);
        // Assert that this is now the head tick
        assertEq(tick.prev, 0);
        // And the first tick we added is next
        assertEq(tick.next, 1);
        // Assert that this is now the head tick
        assertEq(tickStorage.headTickId(), 2);
        // Assert that the tickUpper is updated to this tick
        assertEq(tickStorage.tickUpperId(), 2);
        assertEq(tickStorage.lastInitializedTickId(), 2);
    }

    function test_initializeTickReturnsExistingTickAtHead_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        uint128 id2 = tickStorage.initializeTickIfNeeded(0, price);
        assertEq(id2, 1);
    }

    function test_initializeTickReturnsExistingTick_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        uint128 id2 = tickStorage.initializeTickIfNeeded(1, 2e18);
        assertEq(id2, 2);

        // Try to initialize the same tick again, should return the same id
        uint128 id3 = tickStorage.initializeTickIfNeeded(1, 2e18);
        assertEq(id3, 2);
    }

    function test_initializeTickWithWrongPrice_reverts() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = id;
        price = 0;
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(prev, price);
    }

    function test_initializeTickWithWrongPriceBetweenTicks_reverts() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        tickStorage.initializeTickIfNeeded(1, 2e18);

        // Wrong price, between ticks must be increasing
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(1, 3e18);
    }

    function test_initializeTickBeforeHeadWithWrongPrice_reverts() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = 0;
        // Wrong price, head must be less than all other ticks
        price = 2e18;
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(prev, price);
    }

    function test_updateTickNewTickAtHead_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        tickStorage.updateTick(1, true, 1e18);
        tickStorage.updateTick(1, false, 1e18);
        assertEq(tickStorage.getTick(1).demand.currencyDemand, 1e18);
        assertEq(tickStorage.getTick(1).demand.tokenDemand, 1e18);
    }

    function test_getLowerTickForPriceAtPrice_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        Tick memory tick = tickStorage.getLowerTickForPrice(1e18);
        assertEq(tick.id, 1);
        assertEq(tick.price, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getLowerTickForPriceAboveTickReturnsHighestTick_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        // Price is above the highest tick, so the highest tick is returned
        Tick memory tick = tickStorage.getLowerTickForPrice(2e18);
        assertEq(tick.id, 1);
        assertEq(tick.price, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getLowerTickForPriceBelowTick_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = id;
        price = 2e18;
        id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 2);

        Tick memory tick = tickStorage.getLowerTickForPrice(1.5e18);
        assertEq(tick.id, 1);
        assertEq(tick.price, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);

        price = 4e18;
        id = tickStorage.initializeTickIfNeeded(id, price);
        assertEq(id, 3);

        tick = tickStorage.getLowerTickForPrice(3e18);
        assertEq(tick.id, 2);
        assertEq(tick.price, 2e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }
}
