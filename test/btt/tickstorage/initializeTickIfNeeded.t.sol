// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ITickStorage} from 'twap-auction/TickStorage.sol';

import {MockTickStorage} from 'btt/mocks/MockTickStorage.sol';

import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract InitializeTickIfNeededTest is BttBase {
    using stdStorage for StdStorage;

    uint256 internal tickSpacing;
    uint256 internal floorPrice;
    uint256 internal prevPrice;
    uint256 internal price;
    MockTickStorage internal tickStorage;

    modifier deployTickStorage(uint128 _tickSpacing, uint64 _floorIndex) {
        tickSpacing = bound(_tickSpacing, 2, type(uint128).max);
        floorPrice = tickSpacing * bound(_floorIndex, 1, type(uint64).max);

        tickStorage = new MockTickStorage(tickSpacing, floorPrice);

        _;
    }

    function test_WhenPriceIsNotPerfectlyDivisibleByTickSpacing(
        uint128 _tickSpacing,
        uint64 _floorIndex,
        uint256 _price
    ) external deployTickStorage(_tickSpacing, _floorIndex) {
        // it reverts with {TickPriceNotAtBoundary}

        vm.assume(_price % tickSpacing != 0 && _price != type(uint256).max);

        vm.expectRevert(ITickStorage.TickPriceNotAtBoundary.selector);
        tickStorage.initializeTickIfNeeded(floorPrice, _price);
    }

    modifier whenPriceIsPerfectlyDivisibleByTickSpacing(uint256 _price) {
        uint256 priceIndex = bound(_price, 0, type(uint256).max) / tickSpacing;
        price = priceIndex * tickSpacing;

        _;
        assertTrue(price % tickSpacing == 0, 'price is not divisible by tick spacing');
    }

    function test_WhenPriceEQMAX_TICK_PTR()
        external
        deployTickStorage(1, 1)
        whenPriceIsPerfectlyDivisibleByTickSpacing(type(uint256).max)
    {
        // it reverts with {InvalidTickPrice}

        prevPrice = floorPrice;

        vm.expectRevert(ITickStorage.InvalidTickPrice.selector);
        tickStorage.initializeTickIfNeeded(prevPrice, price);
    }

    modifier whenPriceLTMAX_TICK_PTR() {
        uint256 priceIndex = bound(price, 1, type(uint256).max - 1) / tickSpacing;
        price = priceIndex * tickSpacing;

        _;
    }

    function test_GivenTickIsAlreadyInitialized(uint128 _tickSpacing, uint64 _floorIndex, uint256 _price)
        external
        deployTickStorage(_tickSpacing, _floorIndex)
        whenPriceIsPerfectlyDivisibleByTickSpacing(_price)
        whenPriceLTMAX_TICK_PTR
    {
        // it returns early

        // Overwrite the storage directly to trigger early initialization.
        stdstore.target(address(tickStorage)).sig(ITickStorage.getTick.selector).with_key(price).depth(0)
            .checked_write(type(uint256).max);

        vm.record();
        tickStorage.initializeTickIfNeeded(prevPrice, price);

        (, bytes32[] memory writes) = vm.accesses(address(tickStorage));
        assertEq(writes.length, 0);
    }

    modifier givenTickIsNotInitialized() {
        _;
    }

    function test_WhenPriceLEPrevPrice(uint128 _tickSpacing, uint64 _floorIndex, uint256 _prevPrice, uint256 _price)
        external
        deployTickStorage(_tickSpacing, _floorIndex)
        whenPriceIsPerfectlyDivisibleByTickSpacing(_price)
        whenPriceLTMAX_TICK_PTR
        givenTickIsNotInitialized
    {
        // it reverts with {TickPreviousPriceInvalid}

        // Need to ensure that the tick is NOT already initialized
        vm.assume(price != floorPrice);

        prevPrice = bound(_prevPrice, price, type(uint256).max);
        assertGe(prevPrice, price);

        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(prevPrice, price);
    }

    modifier whenPriceGTPrevPrice() {
        // Also assume that we do not hit the already initialized path.
        vm.assume(price != floorPrice);

        _;
        assertGt(price, prevPrice, 'price is not greater than prevPrice');
    }

    function test_GivenPrevPriceIsNotInitialized(
        uint128 _tickSpacing,
        uint64 _floorIndex,
        uint256 _prevPrice,
        uint256 _price
    )
        external
        deployTickStorage(_tickSpacing, _floorIndex)
        whenPriceIsPerfectlyDivisibleByTickSpacing(_price)
        whenPriceLTMAX_TICK_PTR
        givenTickIsNotInitialized
        whenPriceGTPrevPrice
    {
        // it reverts with {TickPreviousPriceInvalid}

        price = bound(_price, floorPrice + tickSpacing * 2, (type(uint256).max - 1)) / tickSpacing * tickSpacing;
        prevPrice = bound(_prevPrice, floorPrice + tickSpacing, price - 1) / tickSpacing * tickSpacing;

        vm.assume(price != floorPrice);
        vm.assume(prevPrice != floorPrice);

        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
        tickStorage.initializeTickIfNeeded(prevPrice, price);
    }

    modifier givenPrevPriceIsInitialized() {
        _;
    }

    function test_GivenWeDoNotInsertRightBeforeTheNextActiveTickPrice(
        uint128 _tickSpacing,
        uint64 _floorIndex,
        uint64 _firstTick,
        uint64 _priceTick
    )
        external
        deployTickStorage(_tickSpacing, _floorIndex)
        whenPriceIsPerfectlyDivisibleByTickSpacing(0)
        whenPriceLTMAX_TICK_PTR
        givenTickIsNotInitialized
        whenPriceGTPrevPrice
        givenPrevPriceIsInitialized
    {
        // it loops forward until the parent is found
        // it writes next pointer of new tick
        // it writes next pointer of previous tick
        // it emits {TickInitialized}

        uint256 firstTick = bound(_firstTick, 5, type(uint48).max);
        uint256 firstPrice = floorPrice + firstTick * tickSpacing;

        tickStorage.initializeTickIfNeeded(floorPrice, firstPrice);

        price = floorPrice + bound(_priceTick, firstTick + 1, type(uint64).max) * tickSpacing;

        vm.expectEmit(true, true, true, true, address(tickStorage));
        emit ITickStorage.TickInitialized(price);

        vm.record();
        vm.recordLogs();
        tickStorage.initializeTickIfNeeded(floorPrice, price);
        assertEq(vm.getRecordedLogs().length, 1, 'should emit 1 log');
        (, bytes32[] memory writes) = vm.accesses(address(tickStorage));
        assertEq(writes.length, 2, 'should write 2 slots');

        assertEq(tickStorage.getTick(firstPrice).next, price);
        assertEq(tickStorage.getTick(price).next, type(uint256).max);
    }

    function test_GivenWeInsertRightBeforeTheNextActiveTickPrice(
        uint128 _tickSpacing,
        uint64 _floorIndex,
        uint64 _firstTick,
        uint64 _priceTick
    )
        external
        deployTickStorage(_tickSpacing, _floorIndex)
        whenPriceIsPerfectlyDivisibleByTickSpacing(0)
        whenPriceLTMAX_TICK_PTR
        givenTickIsNotInitialized
        whenPriceGTPrevPrice
        givenPrevPriceIsInitialized
    {
        // it loops forward until the parent is found
        // it writes next pointer of new tick
        // it writes next pointer of previous tick
        // it writes nextActiveTickPrice
        // it emits {TickInitialized}

        uint256 firstTick = bound(_firstTick, 5, type(uint48).max);
        uint256 firstPrice = floorPrice + firstTick * tickSpacing;

        tickStorage.initializeTickIfNeeded(floorPrice, firstPrice);

        price = floorPrice + bound(_priceTick, 1, firstTick - 1) * tickSpacing;

        vm.expectEmit(true, true, true, true, address(tickStorage));
        emit ITickStorage.NextActiveTickUpdated(price);

        vm.expectEmit(true, true, true, true, address(tickStorage));
        emit ITickStorage.TickInitialized(price);

        vm.record();
        vm.recordLogs();
        tickStorage.initializeTickIfNeeded(floorPrice, price);
        assertEq(vm.getRecordedLogs().length, 2, 'should emit 2 log');
        (, bytes32[] memory writes) = vm.accesses(address(tickStorage));
        assertEq(writes.length, 3, 'should write 3 slots');

        assertEq(tickStorage.getTick(floorPrice).next, price);
        assertEq(tickStorage.getTick(price).next, firstPrice);
        assertEq(tickStorage.nextActiveTickPrice(), price);
    }
}
