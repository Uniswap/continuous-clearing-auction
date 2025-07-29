// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick spacing is zero
    error TickSpacingIsZero();
    /// @notice Emitted when a tick is initialized
    /// @param tick The tick
    /// @param sqrtPriceX96 The sqrt price of the tick
    event TickInitialized(int24 tick, uint160 sqrtPriceX96);
}
