// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITickStorage, Tick} from './interfaces/ITickStorage.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';

/// @title TickStorage
/// @notice Abstract contract for handling tick storage
abstract contract TickStorage is ITickStorage {
    /// @notice Mapping of Q96 price levels to tick data
    mapping(uint256 priceQ96 => Tick) private $_ticks;

    /// @notice The Q96 price of the next initialized tick above the clearing price
    /// @dev This will be MAX_TICK_PTR if there are no initialized ticks above the clearing price
    uint256 internal $nextActiveTickPriceQ96;
    /// @notice The Q96 floor price of the auction
    uint256 internal immutable FLOOR_PRICE_Q96;
    /// @notice The Q96 tick spacing of the auction - bids must be placed at discrete tick intervals
    uint256 internal immutable TICK_SPACING_Q96;

    /// @notice Sentinel value for the next pointer of the highest tick in the book
    uint256 public constant MAX_TICK_PTR = type(uint256).max;

    constructor(uint256 _tickSpacingQ96, uint256 _floorPriceQ96) {
        if (_tickSpacingQ96 < ConstantsLib.MIN_TICK_SPACING) revert TickSpacingTooSmall();
        TICK_SPACING_Q96 = _tickSpacingQ96;
        if (_floorPriceQ96 == 0) revert FloorPriceIsZero();
        if (_floorPriceQ96 < ConstantsLib.MIN_FLOOR_PRICE) revert FloorPriceTooLow();
        FLOOR_PRICE_Q96 = _floorPriceQ96;
        // Initialize the Q96 floor price as the first tick
        // _getTick will validate that it is also at a tick boundary
        _getTick(FLOOR_PRICE_Q96).next = MAX_TICK_PTR;
        $nextActiveTickPriceQ96 = MAX_TICK_PTR;
        emit NextActiveTickUpdated(MAX_TICK_PTR);
        emit TickInitialized(FLOOR_PRICE_Q96);
    }

    /// @notice Internal function to get a tick at a Q96 price
    /// @dev The returned tick is not guaranteed to be initialized
    function _getTick(uint256 priceQ96) internal view returns (Tick storage) {
        // Validate `priceQ96` is at a boundary designated by the tick spacing
        if (priceQ96 % TICK_SPACING_Q96 != 0) revert TickPriceNotAtBoundary();
        return $_ticks[priceQ96];
    }

    /// @notice Initialize a tick at `priceQ96` if it does not exist already
    /// @dev `prevPriceQ96` MUST be the Q96 price of an initialized tick before the new Q96 price.
    ///      Ideally, it is the Q96 price of the tick immediately preceding the desired Q96 price. If not,
    ///      we will iterate through the ticks until we find the next Q96 price, which requires more gas.
    ///      If `priceQ96` is < `$nextActiveTickPriceQ96`, then `priceQ96` will become the next active tick price.
    /// @param prevPriceQ96 The Q96 price of the previous tick
    /// @param priceQ96 The Q96 price of the tick
    function _initializeTickIfNeeded(uint256 prevPriceQ96, uint256 priceQ96) internal {
        if (priceQ96 == MAX_TICK_PTR) revert InvalidTickPrice();
        // _getTick will validate that `priceQ96` is at a boundary designated by the tick spacing
        Tick storage $newTick = _getTick(priceQ96);
        // Early return if the tick is already initialized
        if ($newTick.next != 0) return;
        // Otherwise, we need to iterate through the linked list to find the correct position for the new tick
        // Require that `prevPriceQ96` is less than `priceQ96` since we can only iterate forward
        if (prevPriceQ96 >= priceQ96) revert TickPreviousPriceInvalid();
        uint256 nextPriceQ96 = _getTick(prevPriceQ96).next;
        // Revert if the next Q96 price is 0 as that means the `prevPriceQ96` hint was not an initialized tick
        if (nextPriceQ96 == 0) revert TickPreviousPriceInvalid();
        // Move the `prevPriceQ96` pointer up until its next pointer is a tick greater than or equal to `priceQ96`
        // If `priceQ96` would be the highest tick in the list, this will iterate until `nextPriceQ96` == MAX_TICK_PTR,
        // which will end the loop since we don't allow for ticks to be initialized at MAX_TICK_PTR.
        // Iterating to find the tick right before `priceQ96` ensures that it is correctly positioned in the linked list.
        while (nextPriceQ96 < priceQ96) {
            prevPriceQ96 = nextPriceQ96;
            nextPriceQ96 = _getTick(nextPriceQ96).next;
        }
        // Update linked list pointers
        $newTick.next = nextPriceQ96;
        _getTick(prevPriceQ96).next = priceQ96;
        // If the next tick is the nextActiveTick, update nextActiveTick to the new tick
        // If the inserted tick precedes the current next active tick, make it the next active tick.
        if (nextPriceQ96 == $nextActiveTickPriceQ96) {
            $nextActiveTickPriceQ96 = priceQ96;
            emit NextActiveTickUpdated(priceQ96);
        }

        emit TickInitialized(priceQ96);
    }

    /// @notice Internal function to add demand to a tick
    /// @param priceQ96 The Q96 price of the tick
    /// @param currencyDemandQ96 The demand to add
    function _updateTickDemand(uint256 priceQ96, uint256 currencyDemandQ96) internal {
        Tick storage $tick = _getTick(priceQ96);
        if ($tick.next == 0) revert CannotUpdateUninitializedTick();
        $tick.currencyDemandQ96 += currencyDemandQ96;
    }

    // Getters
    /// @inheritdoc ITickStorage
    function floorPrice() external view returns (uint256) {
        return FLOOR_PRICE_Q96;
    }

    /// @inheritdoc ITickStorage
    function tickSpacing() external view returns (uint256) {
        return TICK_SPACING_Q96;
    }

    /// @inheritdoc ITickStorage
    function nextActiveTickPrice() external view returns (uint256) {
        return $nextActiveTickPriceQ96;
    }

    /// @inheritdoc ITickStorage
    function ticks(uint256 priceQ96) external view returns (Tick memory) {
        return _getTick(priceQ96);
    }
}
