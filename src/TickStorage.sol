// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BidStorage} from './BidStorage.sol';
import {ITickStorage} from './interfaces/ITickStorage.sol';
import {Bid} from './libraries/BidLib.sol';

struct Tick {
    uint128 id;
    uint128 prev;
    uint128 next;
    uint256 price;
    uint256 sumCurrencyDemand; // Sum of demand in the `currency` (exactIn)
    uint256 sumTokenDemand; // Sum of demand in the `token` (exactOut)
}

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage, BidStorage {
    /// @notice Doubly linked list of ticks, sorted ascending by price
    mapping(uint128 id => Tick) public ticks;
    /// @notice The id of the next tick to be initialized
    uint128 public nextTickId;
    /// @notice The id of the tick directly above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint128 public tickUpperId;
    /// @notice The id of the first tick
    uint128 public headTickId;

    /// @notice Initialize a tick at `price` if its does not exist already
    /// @notice Requires `prev` to be the id of the tick immediately preceding the desired price
    /// @param prev The id of the previous tick
    /// @param price The price of the tick
    /// @return id The id of the tick
    function _initializeTickIfNeeded(uint128 prev, uint256 price) internal returns (uint128 id) {
        uint128 next;
        uint256 nextPrice;

        if (prev == 0) {
            next = headTickId;
            if (next != 0) {
                nextPrice = ticks[next].price;
                if (nextPrice < price) revert TickPriceNotIncreasing();
            }
        } else {
            next = ticks[prev].next;
            uint256 prevPrice = ticks[prev].price;

            if (next != 0) {
                nextPrice = ticks[next].price;
            }

            if (prevPrice >= price || (next != 0 && nextPrice < price)) {
                revert TickPriceNotIncreasing();
            }
        }

        // The tick already exists, return it
        if (nextPrice == price) return next;

        id = nextTickId == 0 ? 1 : nextTickId;
        Tick storage newTick = ticks[id];
        newTick.id = id;
        newTick.prev = prev;
        newTick.next = next;
        newTick.price = price;
        newTick.sumCurrencyDemand = 0;
        newTick.sumTokenDemand = 0;

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
    /// @param bid The bid to add
    function _updateTick(uint128 id, Bid memory bid) internal returns (uint256 bidId) {
        Tick storage tick = ticks[id];

        if (bid.exactIn) {
            tick.sumCurrencyDemand += bid.amount;
        } else {
            tick.sumTokenDemand += bid.amount;
        }

        bid.tickId = id;
        bidId = _createBid(bid);
    }
}
