// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CheckpointStorage} from '../../src/CheckpointStorage.sol';
import {Bid} from '../../src/libraries/BidLib.sol';

contract MockCheckpointStorage is CheckpointStorage {
    function calculateFill(
        Bid memory bid,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) external pure returns (uint256 tokensFilled, uint256 currencySpent) {
        return _calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, mpsDenominator);
    }

    function calculatePartialFill(
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 supply,
        uint24 mpsDelta,
        uint256 resolvedDemandAboveClearingPrice
    ) external pure returns (uint256 tokensFilled) {
        return _calculatePartialFill(bidDemand, tickDemand, supply, mpsDelta, resolvedDemandAboveClearingPrice);
    }
}
