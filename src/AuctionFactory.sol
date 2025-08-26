// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from './Auction.sol';
import {AuctionParameters} from './interfaces/IAuction.sol';
import {IAuctionFactory} from './interfaces/IAuctionFactory.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';

/// @title AuctionFactory
contract AuctionFactory is IAuctionFactory {
    address public constant USE_MSG_SENDER = 0x0000000000000000000000000000000000000001;
    /// @inheritdoc IDistributionStrategy

    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributionContract)
    {
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == USE_MSG_SENDER) parameters.fundsRecipient = msg.sender;

        distributionContract = IDistributionContract(
            address(new Auction{salt: keccak256(abi.encode(msg.sender, salt))}(token, amount, parameters))
        );

        emit AuctionCreated(address(distributionContract), token, amount, configData);
    }
}
