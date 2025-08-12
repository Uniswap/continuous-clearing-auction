// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ITickStorage} from './interfaces/ITickStorage.sol';

import {Bid} from './libraries/BidLib.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';
import {Tick} from './libraries/TickLib.sol';

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    using DemandLib for Demand;
    /// @notice Doubly linked list of ticks, sorted ascending by price

    mapping(uint128 id => Tick) public ticks;
    /// @notice The id of the next tick to be initialized
    uint128 public nextTickId;
    /// @notice The id of the tick directly above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint128 public tickUpperId;
    /// @notice The id of the first tick
    uint128 public headTickId;

    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;

    constructor(uint256 _tickSpacing) {
        tickSpacing = _tickSpacing;
    }

    /// @notice Initialize a tick at `price` if its does not exist already
    /// @notice Requires `prev` to be the id of the tick immediately preceding the desired price
    /// @param prev The id of the previous tick
    /// @param price The price of the tick
    /// @return id The id of the tick
    function _initializeTickIfNeeded(uint128 prev, uint256 price) internal returns (uint128 id) {
        uint128 next = prev == 0 ? headTickId : ticks[prev].next;
        uint256 nextPrice = ticks[next].price;

        // If there is a next tick it cannot be less than the new price
        if (next != 0 && nextPrice < price) revert TickPriceNotIncreasing();
        // If there is a previous tick it cannot be greater than or equal to the new price
        else if (prev != 0 && ticks[prev].price >= price) revert TickPriceNotIncreasing();

        // The tick already exists, return it
        if (nextPrice == price) return next;

        id = nextTickId == 0 ? 1 : nextTickId;
        Tick storage newTick = ticks[id];
        newTick.id = id;
        newTick.prev = prev;
        newTick.next = next;
        newTick.price = price;

        if (prev == 0) {
            // Base case: first tick becomes both head and tickUpper
            headTickId = id;
            tickUpperId = id;
        } else {
            ticks[prev].next = id;
        }
        if (next != 0) {
            ticks[next].prev = id;
        }

        nextTickId = id + 1;

        emit TickInitialized(id, price);
    }

    /// @notice Internal function to add a bid to a tick and update its values
    /// @dev Requires the tick to be initialized
    /// @param id The id of the tick
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    function _updateTickAndTickUpper(uint128 id, bool exactIn, uint256 amount) internal {
        Tick storage tick = ticks[id];

        if (exactIn) {
            tick.demand = tick.demand.addCurrencyAmount(amount);
        } else {
            tick.demand = tick.demand.addTokenAmount(amount);
        }

        // If we initialized a new tick before tickUpper, update tickUpper
        if (tick.next == tickUpperId) {
            tickUpperId = id;
        }
    }

    /// @inheritdoc ITickStorage
    function getUpperTickForPrice(uint256 price) external view returns (Tick memory) {
        uint128 low = headTickId;
        uint128 high = nextTickId - 1;
        while (low < high) {
            uint128 mid = (low + high) / 2;
            if (ticks[mid].price < price) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return ticks[low];
    }
}
