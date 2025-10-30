// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from './Auction.sol';
import {AuctionParameters} from './interfaces/IAuction.sol';
import {IAuctionFactory} from './interfaces/IAuctionFactory.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';

import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';

/// @title AuctionFactory
contract AuctionFactory is IAuctionFactory {
    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        override(IDistributionStrategy)
        returns (IDistributionContract distributionContract)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);

        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the msg.sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = msg.sender;
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = msg.sender;

        distributionContract = IDistributionContract(
            address(new Auction{salt: keccak256(abi.encode(msg.sender, salt))}(token, uint128(amount), parameters))
        );

        emit AuctionCreated(address(distributionContract), token, uint128(amount), abi.encode(parameters));
    }

    /// @inheritdoc IAuctionFactory
    function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
        public
        view
        override(IAuctionFactory)
        returns (address)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the msg.sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = sender;
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = sender;

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(Auction).creationCode, abi.encode(token, uint128(amount), parameters)));
        salt = keccak256(abi.encode(sender, salt));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }
}
