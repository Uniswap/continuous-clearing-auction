// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickStorage} from 'twap-auction/TickStorage.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacing, uint256 _floorPrice) TickStorage(_tickSpacing, _floorPrice) {}

    function updateTickDemand(uint256 price, uint256 demandQ96) external {
        super._updateTickDemand(price, demandQ96);
    }

    function initializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        super._initializeTickIfNeeded(prevPrice, price);
    }
}
