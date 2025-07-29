// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickMath} from 'v4-core/libraries/TickMath.sol';
import {TickBitmap} from 'v4-core/libraries/TickBitmap.sol';
import {ITickStorage} from './interfaces/ITickStorage.sol';
import {Bid} from './libraries/BidLib.sol';

struct TickInfo {
    uint256 sumCurrencyDemand; // Sum of demand in the `currency` (exactIn)
    uint256 sumTokenDemand; // Sum of demand in the `token` (exactOut)
}

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    using TickBitmap for mapping(int16 => uint256);

    mapping(int24 tick => TickInfo) ticks;

    int16 public currentTick;
    int24 immutable tickSpacing;

    constructor(int24 _tickSpacing) {
        if (_tickSpacing == 0) revert TickSpacingIsZero();

        tickSpacing = _tickSpacing;
    }

    function _initializeTick(uint160 sqrtPriceX96) internal returns (int24 tick) {
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        ticks.flipTick(tick, tickSpacing);

        currentTick = tick;

        emit TickInitialized(tick, sqrtPriceX96);
    }

    /// @notice Internal function to add a bid to a tick and update its values
    /// @dev Requires the tick to be initialized
    /// @param bid The bid to add
    function _updateTick(int24 tick, Bid memory bid) internal {
        TickInfo storage tickInfo = ticks[tick];

        if (bid.exactIn) {
            tickInfo.sumCurrencyDemand += bid.amount;
        } else {
            tickInfo.sumTokenDemand += bid.amount;
        }
    }

    function _getTickInfo(int24 tick) internal view returns (TickInfo memory) {
        return ticks[tick];
    }

    function nextGreaterInitializedTick(int24 tick) internal view returns (int24 next, bool initialized) {
        while (!initialized) {
            // False because always one for zero
            (next, initialized) = ticks.nextInitializedTickWithinOneWord(tick, tickSpacing, false);
            // Move forward
            tick = next;
        }
    }
}
