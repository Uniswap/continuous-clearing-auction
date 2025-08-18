// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ITickStorage} from './interfaces/ITickStorage.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {Bid} from './libraries/BidLib.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';

struct Tick {
    uint128 next;
    Demand demand;
}

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    using DemandLib for Demand;

    mapping(uint128 id => Tick) public ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint256 public tickUpperPrice;

    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;

    /// @notice Sentinel value for the next value of the highest tick in the book
    uint128 public constant MAX_TICK_ID = type(uint128).max;

    constructor(uint256 _tickSpacing, uint256 _floorPrice) {
        tickSpacing = _tickSpacing;
        _unsafeInitializeTick(_floorPrice);
    }

    /// @notice Convert a price to an id
    function toId(uint256 price) internal view returns (uint128) {
        require(
            price % (tickSpacing << FixedPoint96.RESOLUTION) == 0,
            'TickStorage: price must be a multiple of tickSpacing'
        );
        return uint128(price / (tickSpacing << FixedPoint96.RESOLUTION));
    }

    /// @notice Convert an id to a price
    function toPrice(uint128 id) internal view returns (uint256) {
        return id * (tickSpacing << FixedPoint96.RESOLUTION);
    }

    /// @notice Get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param price The price of the tick
    function getTick(uint256 price) public view returns (Tick memory) {
        return ticks[toId(price)];
    }

    /// @notice Initialize a tick at `price` without checking for existing ticks
    /// @dev This function is unsafe and should only be used when the tick is guaranteed to be the first in the book
    /// @param price The price of the tick
    function _unsafeInitializeTick(uint256 price) internal returns (uint128 id) {
        id = toId(price);
        ticks[id].next = MAX_TICK_ID;
        tickUpperPrice = price;
        emit TickUpperUpdated(price);
        emit TickInitialized(price);
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev Requires `prevId` to be the id of the tick immediately preceding the desired price
    ///      TickUpper will be updated if the new tick is right before it
    /// @param prevId The id of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint128 prevId, uint256 price) internal returns (uint128 id) {
        id = toId(price);

        // No previous price can be greater than or equal to the new price
        uint128 nextId = ticks[prevId].next;
        if (prevId >= id || (nextId != MAX_TICK_ID && nextId < id)) {
            revert TickPriceNotIncreasing();
        }

        // The tick already exists, early return
        if (nextId == id) return id;

        Tick storage newTick = ticks[id];
        newTick.next = nextId;

        // Link prev to new tick
        ticks[prevId].next = id;

        // If the next tick is the tickUpper, update tickUpper to the new tick
        // In the base case, where next == 0 and tickUpperPrice == 0, this will set tickUpperPrice to price
        if (toPrice(nextId) == tickUpperPrice) {
            tickUpperPrice = price;
            emit TickUpperUpdated(price);
        }

        emit TickInitialized(price);
    }

    /// @notice Internal function to add a bid to a tick and update its values
    /// @dev Requires the tick to be initialized
    /// @param id The id of the tick
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    function _updateTick(uint128 id, bool exactIn, uint256 amount) internal {
        Tick storage tick = ticks[id];

        if (exactIn) {
            tick.demand = tick.demand.addCurrencyAmount(amount);
        } else {
            tick.demand = tick.demand.addTokenAmount(amount);
        }
    }
}
