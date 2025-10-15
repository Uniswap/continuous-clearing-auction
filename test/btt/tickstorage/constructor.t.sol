// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ITickStorage} from 'twap-auction/TickStorage.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {MockTickStorage} from 'btt/mocks/MockTickStorage.sol';

import {BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract ConstructorTest is BttBase {
    uint256 tickSpacing;
    uint256 floorPrice;

    function test_WhenTickSpacingEQ0(uint256 _floorPrice) external {
        // it reverts with {TickSpacingIsZero}

        floorPrice = _floorPrice;

        vm.expectRevert(ITickStorage.TickSpacingIsZero.selector);
        new MockTickStorage(0, floorPrice);
    }

    modifier whenTickSpacingGT0(uint256 _tickSpacing) {
        tickSpacing = bound(_tickSpacing, 1, type(uint256).max);
        _;
    }

    function test_WhenFloorPriceEQ0(uint256 _tickSpacing) external whenTickSpacingGT0(_tickSpacing) {
        // it reverts with {FloorPriceIsZero}

        floorPrice = 0;

        vm.expectRevert(ITickStorage.FloorPriceIsZero.selector);
        new MockTickStorage(tickSpacing, floorPrice);
    }

    modifier whenFloorPriceGT0() {
        _;
        assertGt(floorPrice, 0, 'floor price is 0');
    }

    function test_WhenFloorPriceGTMaxBidPrice(uint256 _tickSpacing, uint256 _floorPrice)
        external
        whenTickSpacingGT0(_tickSpacing)
        whenFloorPriceGT0
    {
        // it reverts with {FloorPriceAboveMaxBidPrice}

        floorPrice = bound(_floorPrice, ConstantsLib.MAX_BID_PRICE, type(uint256).max);
        vm.expectRevert(ITickStorage. FloorPriceAboveMaxBidPrice.selector);
        new MockTickStorage(tickSpacing, floorPrice);
    }

    function test_WhenFloorPriceNotPerfectlyDivisibleByTickSpacing(uint256 _tickSpacing, uint256 _floorPrice)
        external
        whenTickSpacingGT0(_tickSpacing)
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
        whenTickSpacingGT0(_tickSpacing)
        whenFloorPriceGT0
    {
        // it writes FLOOR_PRICE
        // it writes next tick to be MAX_TICK_PTR
        // it writes nextActiveTickPrice to be MAX_TICK_PTR
        // it emits {TickInitialized}
        // it emits {NextActiveTickUpdated}

        tickSpacing = bound(_tickSpacing, 1, ConstantsLib.MAX_BID_PRICE - 1);

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
        assertEq(tickStorage.getTick(floorPrice).next, type(uint256).max);
        assertEq(tickStorage.getTick(floorPrice).currencyDemandQ96, 0);
    }
}
