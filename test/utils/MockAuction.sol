// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(
        uint256 minimumClearingPrice,
        uint24 remainingMpsInAuction,
        ValueX7X7 remainingSupplyX7X7
    ) external view returns (uint256) {
        return _calculateNewClearingPrice(minimumClearingPrice, remainingMpsInAuction, remainingSupplyX7X7);
    }

    function getRolloverSupplyMultiplier() external view returns (ValueX7X7, uint24) {
        return _getRolloverSupplyMultiplier();
    }

    function setRolloverSupplyMultiplier(ValueX7X7 totalClearedX7X7, uint24 cumulativeMps) external {
        _setRolloverSupplyMultiplier(totalClearedX7X7, cumulativeMps);
    }

    function rolloverSupplyMultiplierSet() external view returns (bool) {
        return _rolloverSupplyMultiplierSet;
    }
}
