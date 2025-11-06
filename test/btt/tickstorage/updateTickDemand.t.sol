// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';

import {MockTickStorage} from 'btt/mocks/MockTickStorage.sol';
import {ITickStorage} from 'continuous-clearing-auction/interfaces/ITickStorage.sol';

contract UpdateTickDemandTest is BttBase {
    function test_WhenTickIsUninitialized(uint64 _tickSize, uint64 _floorIndex, uint256 _priceTick, uint128 _demand)
        external
    {
        // it reverts with {CannotUpdateUninitializedTick}

        uint256 tickSize = bound(_tickSize, 2, type(uint64).max);
        uint256 floorPrice = tickSize * bound(_floorIndex, 1, type(uint64).max);
        uint256 price = floorPrice + bound(_priceTick, 1, type(uint64).max) * tickSize;

        MockTickStorage tickStorage = new MockTickStorage(tickSize, floorPrice);

        uint256 expectedDemand = 0;

        assertEq(tickStorage.ticks(price).currencyDemandQ96, expectedDemand);

        vm.expectRevert(ITickStorage.CannotUpdateUninitializedTick.selector);
        tickStorage.updateTickDemand(price, _demand);
    }

    function test_WhenTickIsInitialized(
        uint64 _tickSize,
        uint64 _floorIndex,
        uint256 _priceTick,
        uint128[4] memory _demand
    ) external {
        // it writes the demand increase at the price (note, not necessarily a possible bid)

        uint256 tickSize = bound(_tickSize, 2, type(uint64).max);
        uint256 floorPrice = tickSize * bound(_floorIndex, 1, type(uint64).max);
        uint256 price = floorPrice + bound(_priceTick, 1, type(uint64).max) * tickSize;

        MockTickStorage tickStorage = new MockTickStorage(tickSize, floorPrice);

        tickStorage.initializeTickIfNeeded(floorPrice, price);

        uint256 expectedDemand = 0;

        for (uint256 i = 0; i < _demand.length; i++) {
            assertEq(tickStorage.ticks(price).currencyDemandQ96, expectedDemand);
            tickStorage.updateTickDemand(price, _demand[i]);
            expectedDemand += _demand[i];
        }
        assertEq(tickStorage.ticks(price).currencyDemandQ96, expectedDemand);
    }
}
