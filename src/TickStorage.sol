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

    mapping(uint256 price => Tick) private $_ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no ticks have been initialized yet
    uint256 internal $nextActiveTickPrice;
    /// @inheritdoc ITickStorage
    uint256 public immutable floorPrice;
    /// @inheritdoc ITickStorage
    uint256 public immutable tickSpacing;

    /// @notice Sentinel value for the next value of the highest tick in the book
    uint256 public constant MAX_TICK_PRICE = type(uint256).max;

    constructor(uint256 _tickSpacing, uint256 _floorPrice) {
        if (_tickSpacing == 0) revert TickSpacingIsZero();
        tickSpacing = _tickSpacing;
        // Ensure the floor price is at a tick boundary
        if (_floorPrice % tickSpacing != 0) revert TickPriceNotAtBoundary();
        floorPrice = _floorPrice;
        // Initialize the floor price as the first tick
        $_ticks[_floorPrice].next = MAX_TICK_PRICE;
        $nextActiveTickPrice = _floorPrice;
        emit NextActiveTickUpdated(_floorPrice);
        emit TickInitialized(_floorPrice);
    }

    /// @notice Get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param price The price of the tick
    function getTick(uint256 price) public view returns (Tick memory) {
        return $_ticks[price];
    }

    /// @notice Initialize a tick at `price` if it does not exist already
    /// @dev `prevPrice` MUST be the price of an initialized tick before the new price.
    ///      Ideally, it is the price of the tick immediately preceding the desired price. If not,
    ///      we will iterate through the ticks until we find the next price which requires more gas.
    ///      If `price` is < `nextActiveTickPrice`, then `price` will be set as the nextActiveTickPrice
    /// @param prevPrice The price of the previous tick
    /// @param price The price of the tick
    function _initializeTickIfNeeded(uint256 prevPrice, uint256 price) internal {
        // Validate `price` is at a boundary designated by the tick spacing
        if (price % tickSpacing != 0) revert TickPriceNotAtBoundary();
        if (price == MAX_TICK_PRICE) revert InvalidTickPrice();
        Tick storage $newTick = $_ticks[price];
        // Early return if the tick is already initialized
        if ($newTick.next != 0) return;
        // Otherwise, we need to iterate through the linked list to find the correct position for the new tick
        // Require that `prevPrice` is less than `price` since we can only iterate forward
        if (prevPrice >= price) revert TickPreviousPriceInvalid();
        uint256 nextPrice = $_ticks[prevPrice].next;
        // Revert if the next price is 0 as that means the `prevPrice` hint was not an initialized tick
        if (nextPrice == 0) revert TickPreviousPriceInvalid();
        // Move the `prevPrice` pointer up until its next pointer is a tick greater than or equal to `price`
        // If `price` would be the highest tick in the list, this will iterate until `nextPrice` == MAX_TICK_PRICE,
        // which will end the loop since we don't allow for ticks to be initialized at MAX_TICK_PRICE.
        // Iterating to find the tick right before `price` ensures that it is correctly positioned in the linked list.
        while (nextPrice < price) {
            prevPrice = nextPrice;
            nextPrice = $_ticks[nextPrice].next;
        }
        // Update linked list pointers
        $newTick.next = nextPrice;
        $_ticks[prevPrice].next = price;
        // If the next tick is the nextActiveTick, update nextActiveTick to the new tick
        // In the base case, where next == 0 and nextActiveTickPrice == 0, this will set nextActiveTickPrice to price
        if (nextPrice == $nextActiveTickPrice) {
            $nextActiveTickPrice = price;
            emit NextActiveTickUpdated(price);
        }

        emit TickInitialized(price);
    }

    /// @notice Internal function to add a bid to a tick and update its values
    /// @dev Requires the tick to be initialized
    /// @param price The price of the tick
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    function _updateTick(uint256 price, bool exactIn, uint128 amount) internal {
        Tick storage tick = $_ticks[price];

        if (exactIn) {
            tick.demand = tick.demand.addCurrencyAmount(amount);
        } else {
            tick.demand = tick.demand.addTokenAmount(amount);
        }
    }

    /// @inheritdoc ITickStorage
    function nextActiveTickPrice() external view override(ITickStorage) returns (uint256) {
        return $nextActiveTickPrice;
    }

    /// @inheritdoc ITickStorage
    function ticks(uint256 price) external view override(ITickStorage) returns (Tick memory) {
        return $_ticks[price];
    }
}
