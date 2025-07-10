// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick price is invalid for the given price
    error InvalidTickForPrice();
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Emitted when a tick is initialized
    /// @param id The id of the tick
    /// @param price The price of the tick

    event TickInitialized(uint128 id, uint256 price);
}
