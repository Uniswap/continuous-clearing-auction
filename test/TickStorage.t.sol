// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Tick, TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {Test} from 'forge-std/Test.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing, uint256 _floorPrice) TickStorage(_tickSpacing, _floorPrice) {}

    function initializeTickIfNeeded(uint128 prevId, uint256 price) external returns (uint128 id) {
        id = super._initializeTickIfNeeded(prevId, price);
    }

    function updateTick(uint128 id, bool exactIn, uint256 amount) external {
        super._updateTick(id, exactIn, amount);
    }
}

contract TickStorageTest is Test {
    MockTickStorage public tickStorage;
    uint256 public constant TICK_SPACING = 1e18;
    uint256 public constant FLOOR_PRICE = 1e18;

    function setUp() public {
        tickStorage = new MockTickStorage(TICK_SPACING, FLOOR_PRICE);
    }

    /// @dev Copied from TickStorage.sol
    function toId(uint256 price) internal pure returns (uint128) {
        return uint128(price / TICK_SPACING);
    }

    /// @dev Copied from TickStorage.sol
    function toPrice(uint128 id) internal pure returns (uint256) {
        return id * TICK_SPACING;
    }

    function test_initializeTick_succeeds() public {
        uint128 prev = toId(FLOOR_PRICE);
        uint256 price = 2e18;
        tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.demand.currencyDemand, 0);
        assertEq(tick.demand.tokenDemand, 0);
        // Assert there is no next tick (type(uint128).max)
        assertEq(tick.next, type(uint128).max);
        // Assert the tickUpper is unchanged
        assertEq(tickStorage.tickUpperPrice(), FLOOR_PRICE);
    }

    function test_initializeTickWithPrev_succeeds() public {
        uint256 _tickUpperPrice = tickStorage.tickUpperPrice();
        assertEq(_tickUpperPrice, FLOOR_PRICE);

        uint256 price = 2e18;
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint128).max);
        // new tick is not before tickUpper, so tickUpper is not updated
        assertEq(tickStorage.tickUpperPrice(), _tickUpperPrice);
    }

    function test_initializeTickSetsNext_succeeds() public {
        uint128 prev = toId(FLOOR_PRICE);
        uint256 price = 2e18;
        uint128 id = tickStorage.initializeTickIfNeeded(prev, price);
        Tick memory tick = tickStorage.getTick(price);
        assertEq(tick.next, type(uint128).max);

        uint128 next = tickStorage.initializeTickIfNeeded(id, 3e18);
        tick = tickStorage.getTick(3e18);
        assertEq(tick.next, type(uint128).max);

        tick = tickStorage.getTick(2e18);
        assertEq(tick.next, next);
    }

    function test_initializeTickReturnsExistingTick_succeeds() public {
        // Initialize 2e18
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), 2e18);
        // Same call returns the initialized tick
        uint128 id = tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), 2e18);
        assertEq(id, toId(2e18));
    }

    function test_initializeTickWithWrongPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), 0);
    }

    function test_initializeTickAtFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), FLOOR_PRICE);
    }

    // The tick at 0 id should never be initialized, thus its next value is 0, which should cause a revert
    function test_initializeTickWithZeroPrev_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(0, 2e18);
    }

    function test_initializeTickWithWrongPriceBetweenTicks_reverts() public {
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), 2e18);

        // Wrong price, between ticks must be increasing
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        tickStorage.initializeTickIfNeeded(toId(FLOOR_PRICE), 3e18);
    }
}
