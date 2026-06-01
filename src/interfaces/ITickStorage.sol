// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Each tick contains a pointer to the next Q96 price in the linked list
///         and the cumulative currency demand at the tick's Q96 price level
struct Tick {
    uint256 next;
    uint256 currencyDemandQ96;
}

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick spacing is too small
    error TickSpacingTooSmall();
    /// @notice Error thrown when the floor price is zero
    error FloorPriceIsZero();
    /// @notice Error thrown when the floor price is below the minimum floor price
    error FloorPriceTooLow();
    /// @notice Error thrown when the previous Q96 price hint is invalid (higher than the new Q96 price)
    error TickPreviousPriceInvalid();
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Error thrown when the tick is not initialized
    error TickNotInitialized();
    /// @notice Error thrown when the Q96 price is not at a boundary designated by the tick spacing
    error TickPriceNotAtBoundary();
    /// @notice Error thrown when the tick price is invalid
    error InvalidTickPrice();
    /// @notice Error thrown when trying to update the demand of an uninitialized tick
    error CannotUpdateUninitializedTick();

    /// @notice Emitted when a tick is initialized
    /// @param priceQ96 The Q96 price of the tick
    event TickInitialized(uint256 priceQ96);

    /// @notice Emitted when the nextActiveTick is updated
    /// @param priceQ96 The Q96 price of the tick
    event NextActiveTickUpdated(uint256 priceQ96);

    /// @notice The Q96 price of the next initialized tick above the clearing price
    /// @dev This will be MAX_TICK_PTR if there are no initialized ticks above the clearing price
    /// @return The Q96 price of the next active tick
    function nextActiveTickPrice() external view returns (uint256);

    /// @notice Get the Q96 floor price of the auction
    /// @return The minimum Q96 price for bids
    function floorPrice() external view returns (uint256);

    /// @notice Get the Q96 tick spacing enforced for bid prices
    /// @return The Q96 tick spacing value
    function tickSpacing() external view returns (uint256);

    /// @notice Get a tick at a Q96 price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param priceQ96 The Q96 price of the tick, which must be at a boundary designated by the tick spacing
    /// @return The tick at the given Q96 price
    function ticks(uint256 priceQ96) external view returns (Tick memory);
}
