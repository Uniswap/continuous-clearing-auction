// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Tick, TickStorage} from '../src/TickStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {BidLib} from '../src/libraries/BidLib.sol';
import {MPSLib} from '../src/libraries/MPSLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing, uint256 _floorPrice) TickStorage(_tickSpacing, _floorPrice) {}

    /// @notice Set the nextActiveTickPrice, only for testing
    function setNextActiveTickPrice(uint256 price) external {
        $nextActiveTickPrice = price;
    }

    function initializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        super._initializeTickIfNeeded(prevPrice, price);
    }

    function updateTick(uint256 price, ValueX7 demand) external {
        super._updateTickDemand(price, demand);
    }
}

// Fuzzer has a tendency to assume too many values and I think 5000 is enough to test
// the tick storage logic
/// forge-config: default.fuzz.runs = 5000
/// forge-config: ci.fuzz.runs = 5000
contract TickStorageTest is Test, Assertions {
    uint256 $floorPrice_rounded;
    uint256 $tickSpacing;

    MockTickStorage public tickStorage;

    modifier givenValidDeploymentParams(uint256 _tickSpacing, uint256 _floorPrice) {
        $tickSpacing = _tickSpacing;
        vm.assume(_tickSpacing > 0 && _tickSpacing < BidLib.MAX_BID_PRICE);
        $floorPrice_rounded = helper__roundPriceDownToTickSpacing(_floorPrice, $tickSpacing);
        vm.assume($floorPrice_rounded > 0);
        // Assume that floor price is at least one tick away from max price
        vm.assume($floorPrice_rounded < BidLib.MAX_BID_PRICE - $tickSpacing);
        _;
    }

    function helper__roundPriceDownToTickSpacing(uint256 _price, uint256 _tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return _price - (_price % _tickSpacing);
    }

    function helper__roundPriceUpToTickSpacing(uint256 _price, uint256 _tickSpacing) internal pure returns (uint256) {
        return _price + (_tickSpacing - (_price % _tickSpacing));
    }

    function helper__assumeValidPrice(uint256 _price) internal returns (uint256) {
        _price = _bound(
            _price,
            helper__roundPriceUpToTickSpacing($floorPrice_rounded, $tickSpacing),
            helper__roundPriceDownToTickSpacing(BidLib.MAX_BID_PRICE, $tickSpacing)
        );
        _price = helper__roundPriceDownToTickSpacing(_price, $tickSpacing);
        vm.assume(_price % $tickSpacing == 0);
        vm.assume(_price > $floorPrice_rounded);
        vm.assume(_price < BidLib.MAX_BID_PRICE);
        return _price;
    }

    function helper__assumeUninitializedTick(uint256 _price) internal {
        vm.assume(tickStorage.getTick(_price).next == 0);
    }

    function helper__assumeValidPreviousHint(uint256 _prevPrice, uint256 _price) internal {
        // Assume ordering is right
        vm.assume(_prevPrice < _price);
        // Assume that next price is greater than or equal to the price, also checks initialized for free
        vm.assume(tickStorage.getTick(_prevPrice).next >= _price);
    }

    function test_tickStorage_canBeConstructed_fuzz(uint256 tickSpacing, uint256 floorPrice) public {
        MockTickStorage _tickStorage;
        if (tickSpacing == 0) {
            vm.expectRevert(ITickStorage.TickSpacingIsZero.selector);
            _tickStorage = new MockTickStorage(tickSpacing, floorPrice);
        } else if (floorPrice == 0) {
            vm.expectRevert(ITickStorage.FloorPriceIsZero.selector);
            _tickStorage = new MockTickStorage(tickSpacing, floorPrice);
        } else if (floorPrice >= BidLib.MAX_BID_PRICE) {
            vm.expectRevert(ITickStorage.FloorPriceAboveMaxBidPrice.selector);
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

    function test_initializeUnintializedTick_succeeds(uint256 _floorPrice, uint256 _tickSpacing, uint256 _price)
        public
        givenValidDeploymentParams(_tickSpacing, _floorPrice)
    {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _price = helper__assumeValidPrice(_price);

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_price);
        // $floorPrice_rounded is guaranteed to be initialized already
        tickStorage.initializeTickIfNeeded($floorPrice_rounded, _price);
        Tick memory tick = tickStorage.getTick(_price);
        assertEq(tick.currencyDemandX7, ValueX7.wrap(0));
        // Assert there is no next tick (type(uint256).max)
        assertEq(tick.next, tickStorage.MAX_TICK_PTR());
        // Assert the nextActiveTick is unchanged
        assertEq(tickStorage.nextActiveTickPrice(), $floorPrice_rounded);

        tick = tickStorage.getTick($floorPrice_rounded);
        // Assert the next tick from the floor price is the new tick
        assertEq(tick.next, _price);
    }

    function test_initializeFloorPrice_returnsTick(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        // Hint can be whatever here since the floor price is guaranteed to be initialized
        uint256 _prevPrice,
        uint256 _price
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        _price = helper__assumeValidPrice(_price);

        // Intialze the floor price since it is guaranteed to be initialized already
        tickStorage.initializeTickIfNeeded(_prevPrice, $floorPrice_rounded);
        Tick memory tick = tickStorage.getTick($floorPrice_rounded);
        assertEq(tick.next, type(uint256).max);
        assertEq(tickStorage.nextActiveTickPrice(), $floorPrice_rounded);
    }

    function test_initializeTick_returnsTick(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        // Hint can be whatever here since the floor price is guaranteed to be initialized
        uint256 _prevPrice,
        uint256 _randomPrice,
        uint256 _price
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        _price = helper__assumeValidPrice(_price);
        // Assume that `price` is not initialized yet
        helper__assumeUninitializedTick(_price);

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_price);
        // $floorPrice_rounded is guaranteed to be initialized already
        tickStorage.initializeTickIfNeeded($floorPrice_rounded, _price);
        Tick memory tick = tickStorage.getTick(_price);
        assertEq(tick.next, type(uint256).max);

        // Does not revert, returns the tick
        tickStorage.initializeTickIfNeeded(_randomPrice, _price);
    }

    function test_initializeTickSetsNextActiveTickPrice_whenNextActiveTickPriceIsMax_succeeds(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        uint256 _price
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _price = helper__assumeValidPrice(_price);
        // Assume that `price` is not initialized yet
        helper__assumeUninitializedTick(_price);
        // Set nextActiveTickPrice to MAX_TICK_PRICE
        tickStorage.setNextActiveTickPrice(type(uint256).max);
        assertEq(tickStorage.nextActiveTickPrice(), type(uint256).max);

        // Initializing a tick above the highest tick in the book should set nextActiveTickPrice to the new tick
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.NextActiveTickUpdated(_price);
        tickStorage.initializeTickIfNeeded($floorPrice_rounded, _price);
        assertEq(tickStorage.nextActiveTickPrice(), _price);
    }

    function test_initializeTickPerformsSearchForNextTick_succeeds(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        uint256 _price,
        uint256 _nextPrice
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        // Assume all valid prices
        _price = helper__assumeValidPrice(_price);
        _nextPrice = helper__assumeValidPrice(_nextPrice);
        vm.assume(_price != _nextPrice);
        // Assume both are not initialized
        helper__assumeUninitializedTick(_price);
        helper__assumeUninitializedTick(_nextPrice);

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_price);
        tickStorage.initializeTickIfNeeded($floorPrice_rounded, _price);
        Tick memory tick = tickStorage.getTick(_price);
        assertEq(tick.next, type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_nextPrice);
        // You can pass in $floorPrice_rounded and trigger the search for the next hint
        tickStorage.initializeTickIfNeeded($floorPrice_rounded, _nextPrice);
    }

    function test_initializeTickAtMaxTickPrice_reverts(uint256 _floorPrice, uint256 _prevPrice)
        // Hardcode the tick spacing to 1 for the test to support MAX_PRICE being a valid tick
        public
        givenValidDeploymentParams(1, _floorPrice)
    {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        vm.expectRevert(ITickStorage.InvalidTickPrice.selector);
        tickStorage.initializeTickIfNeeded(_prevPrice, type(uint256).max);
    }

    function test_initializeTickWithZeroPrice_reverts(uint256 _floorPrice, uint256 _tickSpacing, uint256 _prevPrice)
        public
        givenValidDeploymentParams(_tickSpacing, _floorPrice)
    {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(_prevPrice, 0);
    }

    // The tick at 0 id should never be initialized, thus its next value is 0, which should cause a revert
    function test_initializeTickWithZeroPrev_reverts(uint256 _floorPrice, uint256 _tickSpacing, uint256 _price)
        public
        givenValidDeploymentParams(_tickSpacing, _floorPrice)
    {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _price = helper__assumeValidPrice(_price);
        helper__assumeUninitializedTick(_price);
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(0, _price);
    }

    function test_initializeTickWithNonExistentPrev_reverts(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        uint256 _prevPrice,
        uint256 _price
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        _price = helper__assumeValidPrice(_price);
        helper__assumeUninitializedTick(_prevPrice);
        helper__assumeUninitializedTick(_price);
        // Assume correct ordering of hints
        vm.assume(_prevPrice < _price);

        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(_prevPrice, _price);
    }

    function test_initializeTickIfNeeded_withPrevIdGreaterThanId_reverts(
        uint256 _floorPrice,
        uint256 _tickSpacing,
        uint256 _prevPrice,
        uint256 _price
    ) public givenValidDeploymentParams(_tickSpacing, _floorPrice) {
        tickStorage = new MockTickStorage($tickSpacing, $floorPrice_rounded);
        _prevPrice = helper__assumeValidPrice(_prevPrice);
        _price = helper__assumeValidPrice(_price);
        // Assume incorrect ordering of hints
        vm.assume(_prevPrice >= _price);

        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(_prevPrice, _price);
    }
}
