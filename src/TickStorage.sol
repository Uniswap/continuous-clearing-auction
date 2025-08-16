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

    mapping(uint128 id => Tick) public ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint256 public tickUpperPrice;
    /// @notice The id of the first tick
    uint128 public headTickId;

    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;

    constructor(uint256 _tickSpacing) {
        tickSpacing = _tickSpacing;
    }

    /// @notice Convert a price to an id
    function toId(uint256 price) internal view returns (uint128) {
        require(price % tickSpacing == 0, 'TickStorage: price must be a multiple of tickSpacing');
        return uint128(price / tickSpacing);
    }

    /// @notice Convert an id to a price
    function toPrice(uint128 id) internal view returns (uint256) {
        return id * tickSpacing;
    }

    /// @notice Get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param price The price of the tick
    function getTick(uint256 price) public view returns (Tick memory) {
        return ticks[toId(price)];
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev Requires `prevId` to be the id of the tick immediately preceding the desired price
    ///      If `prevId` is 0, attempts to initialize a new tick at the beginning of the list
    ///      TickUpper will be updated if the new tick is right before it
    /// @param prevId The id of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint128 prevId, uint256 price) internal returns (uint128 id) {
        id = toId(price);
        uint128 nextId;
        // No previous tick
        if (prevId == 0) {
            nextId = headTickId;
            // Check for the first tick initialized which will be 0
            if (nextId != 0 && nextId < id) revert TickPriceNotIncreasing();
        } else {
            // No previous price can be greater than or equal to the new price
            nextId = ticks[prevId].next;
            if (prevId >= id || (nextId != 0 && nextId < id)) {
                revert TickPriceNotIncreasing();
            }
        }

        // The tick already exists, early return
        if (nextId == id) return id;

        Tick storage newTick = ticks[id];
        newTick.next = nextId;
        newTick.prev = prevId;

        if (prevId == 0) {
            // First tick becomes head
            headTickId = id;
        } else {
            // Link prev to new tick
            ticks[prevId].next = id;
        }

        // If the next tick is the tickUpper, update tickUpper to the new tick
        // In the base case, where next == 0 and tickUpperPrice == 0, this will set tickUpperPrice to price
        if (toPrice(nextId) == tickUpperPrice) {
            tickUpperPrice = price;
            emit TickUpperUpdated(price);
        }

        if (nextId != 0) {
            // Link prev to new tick
            ticks[nextId].prev = id;
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

    /// @inheritdoc ITickStorage
    function getLowerTickForPrice(uint256 price) external view returns (Tick memory) {
        uint128 currentId = headTickId;
        uint128 lastValidId = headTickId;
        uint128 priceId = toId(price);

        while (currentId != 0) {
            Tick storage currentTick = ticks[currentId];

            if (currentId <= priceId) {
                lastValidId = currentId;
                currentId = currentTick.next;
            } else {
                break;
            }
        }

        return ticks[lastValidId];
    }
}
