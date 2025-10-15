// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

import {MockTickStorage} from 'btt/mocks/MockTickStorage.sol';

contract UpdateTickDemandTest is BttBase {
    function test_WhenCalledWithPriceAndDemand(
        uint64 _tickSize,
        uint64 _floorIndex,
        uint256 _price,
        uint128[4] memory _demand
    ) external {
        // it writes the demand increase at the price (note, not necessarily a possible bid)

        uint256 tickSize = bound(_tickSize, 1, type(uint64).max);
        uint256 floorPrice = tickSize * bound(_floorIndex, 1, type(uint64).max);

        MockTickStorage tickStorage = new MockTickStorage(tickSize, floorPrice);

        uint256 expectedDemand = 0;

        for (uint256 i = 0; i < _demand.length; i++) {
            assertEq(tickStorage.getTick(_price).currencyDemandQ96, expectedDemand);
            tickStorage.updateTickDemand(_price, _demand[i]);
            expectedDemand += _demand[i];
        }
        assertEq(tickStorage.getTick(_price).currencyDemandQ96, expectedDemand);
        assertEq(tickStorage.ticks(_price).currencyDemandQ96, expectedDemand);
    }
}
