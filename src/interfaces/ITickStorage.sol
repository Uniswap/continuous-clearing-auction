// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenCurrencyStorage} from './ITokenCurrencyStorage.sol';

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage is ITokenCurrencyStorage {
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Error thrown when the tick price is not at a tick boundary
    error TickPriceNotAtBoundary();
    /// @notice Emitted when a tick is initialized
    /// @param price The price of the tick

    event TickInitialized(uint256 price);

    /// @notice Emitted when the nextActiveTick is updated
    /// @param price The price of the tick
    event NextActiveTickUpdated(uint256 price);
}
