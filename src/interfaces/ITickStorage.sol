// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Tick} from '../TickStorage.sol';

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Emitted when a tick is initialized
    /// @param price The price of the tick

    event TickInitialized(uint256 price);

    /// @notice Emitted when the nextActiveTick is updated
    /// @param price The price of the tick
    event NextActiveTickUpdated(uint256 price);
}
