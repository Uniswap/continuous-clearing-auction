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
        super._updateTickAndTickUpper(id, exactIn, amount);
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
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = id;
        price = 2e18;
        id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 2);
        Tick memory tick = tickStorage.getTick(id);
        assertEq(tick.price, price);
    }

    function test_initializeTickBeforeHead_succeeds() public {
        uint128 prev = 0;
        uint256 price = 2e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = 0;
        price = 1e18;
        id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 2);
        Tick memory tick = tickStorage.getTick(id);
        assertEq(tick.price, 1e18);
        // Assert that this is now the head tick
        assertEq(tick.prev, 0);
        // And the first tick we added is next
        assertEq(tick.next, 1);
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

    function test_getUpperTickForPriceAtPrice_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        Tick memory tick = tickStorage.getUpperTickForPrice(1e18);
        assertEq(tick.id, 1);
        assertEq(tick.price, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getUpperTickForPriceAboveTickReturnsHighestTick_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        // Price is above the highest tick, so the highest tick is returned
        Tick memory tick = tickStorage.getUpperTickForPrice(2e18);
        assertEq(tick.id, 1);
        assertEq(tick.price, 1e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }

    function test_getUpperTickForPriceBelowTick_succeeds() public {
        uint128 prev = 0;
        uint256 price = 1e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 1);

        prev = id;
        price = 2e18;
        id = tickStorage.initializeTickIfNeeded(prev, price);
        assertEq(id, 2);

        Tick memory tick = tickStorage.getUpperTickForPrice(1.5e18);
        assertEq(tick.id, 2);
        assertEq(tick.price, 2e18);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
    }
}
