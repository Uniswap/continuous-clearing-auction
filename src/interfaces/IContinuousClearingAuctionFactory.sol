// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDistributionStrategy} from './external/IDistributionStrategy.sol';

/// @title IContinuousClearingAuctionFactory
interface IContinuousClearingAuctionFactory is IDistributionStrategy {
    /// @notice Error thrown when the amount is invalid
    error InvalidTokenAmount(uint256 amount);

    /// @notice Emitted when an auction is created
    /// @param auction The address of the auction contract
    /// @param token The address of the token
    /// @param amount The amount of tokens to sell
    /// @param configData The configuration data for the auction
    event AuctionCreated(address indexed auction, address indexed token, uint256 amount, bytes configData);

    /// @notice Get the address of an auction contract
    /// @param token The address of the token
    /// @param amount The amount of tokens to sell
    /// @param configData The configuration data for the auction
    /// @param salt The salt to use for the deterministic deployment
    /// @param sender The sender of the initializeDistribution transaction
    /// @return The address of the auction contract
    function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
        external
        view
        returns (address);
}
