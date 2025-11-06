// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';

import {MockTickStorage} from 'btt/mocks/MockTickStorage.sol';
import {ITickStorage} from 'continuous-clearing-auction/TickStorage.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';

contract ConstructorTest is BttBase {
    uint256 tickSpacing;
    uint256 floorPrice;

    function test_WhenTickSpacingTooSmall(uint256 _floorPrice, uint256 _tickSpacing) external {
        // it reverts with {TickSpacingTooSmall}

        floorPrice = _floorPrice;
        _tickSpacing = bound(_tickSpacing, 0, 1);

        vm.expectRevert(ITickStorage.TickSpacingTooSmall.selector);
        new MockTickStorage(_tickSpacing, floorPrice);
    }

    modifier whenTickSpacingValid(uint256 _tickSpacing) {
        tickSpacing = bound(_tickSpacing, 2, type(uint256).max);
        _;
    }

    function test_WhenFloorPriceEQ0(uint256 _tickSpacing) external whenTickSpacingValid(_tickSpacing) {
        // it reverts with {FloorPriceIsZero}

        floorPrice = 0;

        vm.expectRevert(ITickStorage.FloorPriceIsZero.selector);
        new MockTickStorage(tickSpacing, floorPrice);
    }

    modifier whenFloorPriceGT0() {
        _;
        assertGt(floorPrice, 0, 'floor price is 0');
    }

    function test_WhenFloorPriceNotPerfectlyDivisibleByTickSpacing(uint256 _tickSpacing, uint256 _floorPrice)
        external
        whenTickSpacingValid(_tickSpacing)
        whenFloorPriceGT0
    {
        // it reverts with {TickPriceNotAtBoundary}

        vm.assume(_floorPrice < ConstantsLib.MAX_BID_PRICE && _floorPrice % tickSpacing != 0);
        floorPrice = _floorPrice;

        vm.expectRevert(ITickStorage.TickPriceNotAtBoundary.selector);
        new MockTickStorage(tickSpacing, floorPrice);
    }

    function test_WhenFloorPriceIsPerfectlyDivisibleByTickSpacing(uint256 _tickSpacing, uint256 _floorPrice)
        external
        whenTickSpacingValid(_tickSpacing)
        whenFloorPriceGT0
    {
        // it writes FLOOR_PRICE
        // it writes next tick to be MAX_TICK_PTR
        // it writes nextActiveTickPrice to be MAX_TICK_PTR
        // it emits {TickInitialized}
        // it emits {NextActiveTickUpdated}

        tickSpacing = bound(_tickSpacing, 2, ConstantsLib.MAX_BID_PRICE - 1);

        uint256 tickIndex = bound(_floorPrice, 1, (ConstantsLib.MAX_BID_PRICE - 1) / tickSpacing);
        floorPrice = tickIndex * tickSpacing;

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.NextActiveTickUpdated(type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(floorPrice);

        MockTickStorage tickStorage = new MockTickStorage(tickSpacing, floorPrice);

        assertEq(tickStorage.floorPrice(), floorPrice);
        assertEq(tickStorage.tickSpacing(), tickSpacing);
        assertEq(tickStorage.nextActiveTickPrice(), type(uint256).max);
        assertEq(tickStorage.ticks(floorPrice).next, type(uint256).max);
        assertEq(tickStorage.ticks(floorPrice).currencyDemandQ96, 0);
    }
}
