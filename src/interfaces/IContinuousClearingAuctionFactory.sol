// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDistributorFactory} from 'liquidity-launcher/src/interfaces/IDistributorFactory.sol';
import {IProtocolFeeController} from 'liquidity-launcher/src/interfaces/IProtocolFeeController.sol';

/// @title IContinuousClearingAuctionFactory
interface IContinuousClearingAuctionFactory is IDistributorFactory {
    /// @notice Error thrown when the amount is invalid
    error InvalidTokenAmount(uint256 amount);

    /// @notice Emitted when an auction is created
    /// @param auction The address of the auction contract
    /// @param token The address of the token
    /// @param amount The amount of tokens to sell
    /// @param configData The configuration data for the auction
    event AuctionCreated(address indexed auction, address indexed token, uint256 amount, bytes configData);

    /// @notice The protocol fee controller used for auctions created by this factory
    /// @dev Deploy a new factory to use a different protocol fee controller.
    function protocolFeeController() external view returns (IProtocolFeeController);
}
