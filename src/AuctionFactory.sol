// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Auction} from './Auction.sol';
import {AuctionParameters} from './Base.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';

/// @title AuctionFactory
contract AuctionFactory is IDistributionStrategy {
    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData)
        external
        returns (IDistributionContract distributionContract)
    {
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));

        bytes32 salt = keccak256(abi.encode(token, amount, parameters));
        distributionContract = IDistributionContract(address(new Auction{salt: salt}(token, amount, parameters)));
    }
}
