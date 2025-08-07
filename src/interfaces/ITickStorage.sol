// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Tick} from '../libraries/TickLib.sol';

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Emitted when a tick is initialized
    /// @param id The id of the tick
    /// @param price The price of the tick

    event TickInitialized(uint128 id, uint256 price);

    /// @notice Get the tick closest to `price`, if no tick exists at `price` then return the closest tick above it
    /// @notice If the price is greater than the highest tick, then the highest tick is returned
    /// @dev This function is not gas efficient and should only be called offchain
    /// @param price The price to get the tick for
    /// @return tick The tick closest to `price`
    function getUpperTickForPrice(uint256 price) external view returns (Tick memory);
}
