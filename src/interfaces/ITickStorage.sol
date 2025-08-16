// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Tick} from '../libraries/TickLib.sol';

/// @title ITickStorage
/// @notice Interface for the TickStorage contract
interface ITickStorage {
    /// @notice Error thrown when the tick price is not increasing
    error TickPriceNotIncreasing();
    /// @notice Emitted when a tick is initialized
    /// @param price The price of the tick

    event TickInitialized(uint256 price);

    /// @notice Emitted when the tickUpper is updated
    /// @param price The price of the tick
    event TickUpperUpdated(uint256 price);

    /// @notice Get the closest tick at or below `price`
    /// @dev This function is not gas efficient and should only be called offchain
    /// @param price The price to get the tick for
    /// @return tick returned tick
    function getLowerTickForPrice(uint256 price) external view returns (Tick memory);
}
