// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Tick} from '../TickStorage.sol';

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the floor price is above Uniswap v4's maximum tick price
    error FloorPriceAboveMaxBidPrice();
    /// @notice Error thrown when the tick spacing is too small
    error TickSpacingTooSmall();
    /// @notice Error thrown when the floor price is zero
    error FloorPriceIsZero();
    /// @notice Error thrown when the previous price hint is invalid (higher than the new price)
    error TickPreviousPriceInvalid();
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Error thrown when the price is not at a boundary designated by the tick spacing
    error TickPriceNotAtBoundary();
    /// @notice Error thrown when the tick price is invalid
    error InvalidTickPrice();
    /// @notice Error thrown when trying to update the demand of an uninitialized tick
    error CannotUpdateUninitializedTick();

    /// @notice Emitted when a tick is initialized
    /// @param price The price of the tick
    event TickInitialized(uint256 price);

    /// @notice Emitted when the nextActiveTick is updated
    /// @param price The price of the tick
    event NextActiveTickUpdated(uint256 price);

    /// @notice Get a tick at a price
    /// @dev The returned tick is not guaranteed to be initialized
    /// @param price The price of the tick
    /// @return The tick at the given price
    function getTick(uint256 price) external view returns (Tick memory);

    /// @notice The price of the next initialized tick above the clearing price
    /// @dev This will be equal to the clearingPrice if no ticks have been initialized yet
    /// @return The price of the next active tick
    function nextActiveTickPrice() external view returns (uint256);

    /// @notice Get the floor price of the auction
    /// @return The minimum price for bids
    function floorPrice() external view returns (uint256);

    /// @notice Get the tick spacing enforced for bid prices
    /// @return The tick spacing value
    function tickSpacing() external view returns (uint256);

    /// @notice Get a tick at a price
    function ticks(uint256 price) external view returns (Tick memory);
}
