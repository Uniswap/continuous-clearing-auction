// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ITickStorage} from './interfaces/ITickStorage.sol';

import {Bid} from './libraries/BidLib.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';

struct Tick {
    uint256 next;
    Demand demand;
}

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    using DemandLib for Demand;

    mapping(uint256 price => Tick) public ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint256 public tickUpperPrice;

    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;

    /// @notice Sentinel value for the next value of the highest tick in the book
    uint256 public constant MAX_TICK_PRICE = type(uint256).max;
    uint256 public constant MIN_TICK_PRICE = 0;

    constructor(uint256 _tickSpacing, uint256 _floorPrice) {
        tickSpacing = _tickSpacing;
        _unsafeInitializeTick(_floorPrice);
    }

    /// @notice Get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param price The price of the tick
    function getTick(uint256 price) public view returns (Tick memory) {
        return ticks[price];
    }

    /// @notice Initialize a tick at `price` without checking for existing ticks
    /// @dev This function is unsafe and should only be used when the tick is guaranteed to be the first in the book
    /// @param price The price of the tick
    function _unsafeInitializeTick(uint256 price) internal {
        ticks[price].next = MAX_TICK_PRICE;
        tickUpperPrice = price;
        emit TickUpperUpdated(price);
        emit TickInitialized(price);
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev Requires `prevId` to be the id of the tick immediately preceding the desired price
    ///      TickUpper will be updated if the new tick is right before it
    /// @param prevPrice The price of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint256 prevPrice, uint256 price) internal {
        // No previous price can be greater than or equal to the new price
        uint256 nextPrice = ticks[prevPrice].next;
        if (prevPrice >= price || (nextPrice != MAX_TICK_PRICE && nextPrice < price)) {
            revert TickPriceNotIncreasing();
        }

        if(price % tickSpacing != 0) {
            revert TickPriceNotAtBoundary();
        }

        // The tick already exists, early return
        if (nextPrice == price) return;

        Tick storage newTick = ticks[price];
        newTick.next = nextPrice;

        // Link prev to new tick
        ticks[prevPrice].next = price;

        // If the next tick is the tickUpper, update tickUpper to the new tick
        // In the base case, where next == 0 and tickUpperPrice == 0, this will set tickUpperPrice to price
        if (nextPrice == tickUpperPrice) {
            tickUpperPrice = price;
            emit TickUpperUpdated(price);
        }

        emit TickInitialized(price);
    }

    /// @notice Internal function to add a bid to a tick and update its values
    /// @dev Requires the tick to be initialized
    /// @param price The price of the tick
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    function _updateTick(uint256 price, bool exactIn, uint256 amount) internal {
        Tick storage tick = ticks[price];

        if (exactIn) {
            tick.demand = tick.demand.addCurrencyAmount(amount);
        } else {
            tick.demand = tick.demand.addTokenAmount(amount);
        }
    }
}
