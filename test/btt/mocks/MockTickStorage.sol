// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickStorage} from 'continuous-clearing-auction/TickStorage.sol';

contract MockTickStorage is TickStorage {
    constructor(uint256 _tickSpacingQ96, uint256 _floorPriceQ96) TickStorage(_tickSpacingQ96, _floorPriceQ96) {}

    function updateTickDemand(uint256 priceQ96, uint256 demandQ96) external {
        super._updateTickDemand(priceQ96, demandQ96);
    }

    function initializeTickIfNeeded(uint256 prevPriceQ96, uint256 priceQ96) external {
        super._initializeTickIfNeeded(prevPriceQ96, priceQ96);
    }
}
