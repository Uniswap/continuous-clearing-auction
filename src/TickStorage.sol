// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

    /// @inheritdoc ITickStorage
    uint256 public nextActiveTickPrice;
    /// @notice The floor price of the auction
    uint256 internal immutable FLOOR_PRICE;
    /// @notice The tick spacing of the auction - bids must be placed at discrete tick intervals
    uint256 internal immutable TICK_SPACING;

    /// @notice Sentinel value for the next value of the highest tick in the book
    uint256 public constant MAX_TICK_PRICE = type(uint256).max;

    constructor(uint256 _tickSpacing, uint256 _floorPrice) {
        TICK_SPACING = _tickSpacing;
        FLOOR_PRICE = _floorPrice;
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
        nextActiveTickPrice = price;
        emit NextActiveTickUpdated(price);
        emit TickInitialized(price);
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev Requires `prevId` to be the id of the tick immediately preceding the desired price
    ///      NextActiveTick will be updated if the new tick is right before it
    /// @param prevPrice The price of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint256 prevPrice, uint256 price) internal {
        // No previous price can be greater than or equal to the new price
        uint256 nextPrice = ticks[prevPrice].next;

        if (prevPrice >= price) {
            revert TickPreviousPriceInvalid();
        }

        if (nextPrice != MAX_TICK_PRICE && nextPrice < price) {
            revert TickPriceNotIncreasing();
        }

        if (price % TICK_SPACING != 0) revert TickPriceNotAtBoundary();

        // The tick already exists, early return
        if (nextPrice == price) return;

        Tick storage newTick = ticks[price];
        newTick.next = nextPrice;

        // Link prev to new tick
        ticks[prevPrice].next = price;

        // If the next tick is the nextActiveTick, update nextActiveTick to the new tick
        // In the base case, where next == 0 and nextActiveTickPrice == 0, this will set nextActiveTickPrice to price
        if (nextPrice == nextActiveTickPrice) {
            nextActiveTickPrice = price;
            emit NextActiveTickUpdated(price);
        }

        emit TickInitialized(price);
    }

    /// @notice Internal function to add demand to a tick
    /// @param price The price of the tick
    /// @param demand The demand to add
    function _updateTickDemand(uint256 price, Demand memory demand) internal {
        Tick storage tick = ticks[price];
        tick.demand = tick.demand.add(demand);
    }

    // Getters
    /// @inheritdoc ITickStorage
    function floorPrice() external view override(ITickStorage) returns (uint256) {
        return FLOOR_PRICE;
    }

    /// @inheritdoc ITickStorage
    function tickSpacing() external view override(ITickStorage) returns (uint256) {
        return TICK_SPACING;
    }
}
