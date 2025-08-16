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

    mapping(uint256 price => Tick) public ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no other prices have been discovered
    uint256 public tickUpperPrice;
    /// @notice The price of the first tick
    uint256 public headTickPrice;

    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;

    constructor(uint256 _tickSpacing) {
        tickSpacing = _tickSpacing;
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev Requires `prevPrice` to be the price of the tick immediately preceding the desired price
    ///      If `prevPrice` is 0, attempts to initialize a new tick at the beginning of the list
    ///      TickUpper will be updated if the new tick is right before it
    /// @param prevPrice The price of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint256 prevPrice, uint256 price) internal {
        uint256 nextPrice;
        // No previous tick
        if (prevPrice == 0) {
            nextPrice = headTickPrice;
            // Check for the first tick initialized which will be 0
            if (nextPrice != 0 && nextPrice < price) revert TickPriceNotIncreasing();
        } else {
            // No previous price can be greater than or equal to the new price
            nextPrice = ticks[prevPrice].next;
            if (prevPrice >= price || (nextPrice != 0 && nextPrice < price)) {
                revert TickPriceNotIncreasing();
            }
        }

        // The tick already exists, early return
        if (nextPrice == price) return;

        Tick storage newTick = ticks[price];
        newTick.next = nextPrice;
        newTick.prev = prevPrice;

        if (prevPrice == 0) {
            // First tick becomes head
            headTickPrice = price;
        } else {
            // Link prev to new tick
            ticks[prevPrice].next = price;
        }

        // If the next tick is the tickUpper, update tickUpper to the new tick
        // In the base case, where next == 0 and tickUpperPrice == 0, this will set tickUpperPrice to price
        if (nextPrice == tickUpperPrice) {
            tickUpperPrice = price;
            emit TickUpperUpdated(price);
        }

        if (nextPrice != 0) {
            // Link prev to new tick
            ticks[nextPrice].prev = price;
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

    /// @inheritdoc ITickStorage
    function getLowerTickForPrice(uint256 price) external view returns (Tick memory) {
        uint256 currentPrice = headTickPrice;
        uint256 lastValidPrice = headTickPrice;

        while (currentPrice != 0) {
            Tick storage currentTick = ticks[currentPrice];

            if (currentPrice <= price) {
                lastValidPrice = currentPrice;
                currentPrice = currentTick.next;
            } else {
                break;
            }
        }

        return ticks[lastValidPrice];
    }
}
