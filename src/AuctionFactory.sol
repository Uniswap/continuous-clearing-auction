// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Auction} from './Auction.sol';
import {AuctionParameters} from './Base.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';

/// @title AuctionFactory
contract AuctionFactory is IDistributionStrategy {
    /// @notice Thrown when the token is invalid
    error InvalidToken();
    /// @notice Thrown when the amount is invalid
    error InvalidAmount();

    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData)
        external
        returns (IDistributionContract distributionContract)
    {
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));

        if (parameters.token != token) revert InvalidToken();
        if (parameters.totalSupply != amount) revert InvalidAmount();

        bytes32 salt = keccak256(configData);
        distributionContract = IDistributionContract(address(new Auction{salt: salt}(parameters)));
    }
}
