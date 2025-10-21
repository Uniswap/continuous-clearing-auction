// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITickStorage} from './interfaces/ITickStorage.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';

struct Tick {
    uint256 next;
    uint256 currencyDemandQ96;
}

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    /// @notice Mapping of price levels to tick data
    mapping(uint256 price => Tick) private $_ticks;

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no ticks have been initialized yet
    uint256 internal $nextActiveTickPrice;
    /// @notice The floor price of the auction
    uint256 internal immutable FLOOR_PRICE;
    /// @notice The tick spacing of the auction - bids must be placed at discrete tick intervals
    uint256 internal immutable TICK_SPACING;

    /// @notice Sentinel value for the next pointer of the highest tick in the book
    uint256 public constant MAX_TICK_PTR = type(uint256).max;

    constructor(uint256 _tickSpacing, uint256 _floorPrice) {
        if (_tickSpacing <= 1) revert TickSpacingTooSmall();
        TICK_SPACING = _tickSpacing;
        if (_floorPrice == 0) revert FloorPriceIsZero();
        if (_floorPrice > ConstantsLib.MAX_BID_PRICE) revert FloorPriceAboveMaxBidPrice();
        FLOOR_PRICE = _floorPrice;
        // Initialize the floor price as the first tick
        // _getTick will validate that it is also at a tick boundary
        _getTick(FLOOR_PRICE).next = MAX_TICK_PTR;
        $nextActiveTickPrice = MAX_TICK_PTR;
        emit NextActiveTickUpdated(MAX_TICK_PTR);
        emit TickInitialized(FLOOR_PRICE);
    }

    /// @inheritdoc ITickStorage
    function getTick(uint256 price) public view returns (Tick memory) {
        return _getTick(price);
    }

    /// @notice Internal function to get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    function _getTick(uint256 price) internal view returns (Tick storage) {
        // Validate `price` is at a boundary designated by the tick spacing
        if (price % TICK_SPACING != 0) revert TickPriceNotAtBoundary();
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
        if (price == MAX_TICK_PTR) revert InvalidTickPrice();
        // _getTick will validate that `price` is at a boundary designated by the tick spacing
        Tick storage $newTick = _getTick(price);
        // Early return if the tick is already initialized
        if ($newTick.next != 0) return;
        // Otherwise, we need to iterate through the linked list to find the correct position for the new tick
        // Require that `prevPrice` is less than `price` since we can only iterate forward
        if (prevPrice >= price) revert TickPreviousPriceInvalid();
        uint256 nextPrice = _getTick(prevPrice).next;
        // Revert if the next price is 0 as that means the `prevPrice` hint was not an initialized tick
        if (nextPrice == 0) revert TickPreviousPriceInvalid();
        // Move the `prevPrice` pointer up until its next pointer is a tick greater than or equal to `price`
        // If `price` would be the highest tick in the list, this will iterate until `nextPrice` == MAX_TICK_PTR,
        // which will end the loop since we don't allow for ticks to be initialized at MAX_TICK_PTR.
        // Iterating to find the tick right before `price` ensures that it is correctly positioned in the linked list.
        while (nextPrice < price) {
            prevPrice = nextPrice;
            nextPrice = _getTick(nextPrice).next;
        }
        // Update linked list pointers
        $newTick.next = nextPrice;
        _getTick(prevPrice).next = price;
        // If the next tick is the nextActiveTick, update nextActiveTick to the new tick
        // In the base case, where next == 0 and nextActiveTickPrice == 0, this will set nextActiveTickPrice to price
        if (nextPrice == $nextActiveTickPrice) {
            $nextActiveTickPrice = price;
            emit NextActiveTickUpdated(price);
        }

        emit TickInitialized(price);
    }

    /// @notice Internal function to add demand to a tick
    /// @param price The price of the tick
    /// @param currencyDemandQ96 The demand to add
    function _updateTickDemand(uint256 price, uint256 currencyDemandQ96) internal {
        Tick storage $tick = _getTick(price);
        if ($tick.next == 0) revert CannotUpdateUninitializedTick();
        $tick.currencyDemandQ96 += currencyDemandQ96;
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

    /// @inheritdoc ITickStorage
    function nextActiveTickPrice() external view override(ITickStorage) returns (uint256) {
        return $nextActiveTickPrice;
    }

    /// @inheritdoc ITickStorage
    function ticks(uint256 price) external view override(ITickStorage) returns (Tick memory) {
        return _getTick(price);
    }
}
