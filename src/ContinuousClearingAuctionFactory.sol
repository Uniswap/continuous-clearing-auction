// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from './ContinuousClearingAuction.sol';
import {AuctionParameters} from './interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from './interfaces/IContinuousClearingAuctionFactory.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';
import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {IProtocolFeeController} from 'liquidity-launcher/src/interfaces/IProtocolFeeController.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';

/// @title ContinuousClearingAuctionFactory
/// @notice Deploy a new factory to use a different protocol fee controller for newly created auctions.
/// @custom:security-contact security@uniswap.org
contract ContinuousClearingAuctionFactory is IContinuousClearingAuctionFactory {
    /// @notice The protocol fee controller to use for all created auctions
    IProtocolFeeController public immutable PROTOCOL_FEE_CONTROLLER;

    constructor(address _protocolFeeController) {
        PROTOCOL_FEE_CONTROLLER = IProtocolFeeController(_protocolFeeController);
    }

    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributionContract)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);

        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the msg.sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = msg.sender;
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = msg.sender;

        distributionContract = IDistributionContract(
            address(
                new ContinuousClearingAuction{salt: keccak256(abi.encode(msg.sender, salt))}(
                    token, uint128(amount), parameters, address(PROTOCOL_FEE_CONTROLLER)
                )
            )
        );

        emit AuctionCreated(address(distributionContract), token, uint128(amount), abi.encode(parameters));
    }

    /// @inheritdoc IContinuousClearingAuctionFactory
    function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
        external
        view
        returns (address)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the msg.sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = sender;
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = sender;

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(ContinuousClearingAuction).creationCode,
                abi.encode(token, uint128(amount), parameters, address(PROTOCOL_FEE_CONTROLLER))
            )
        );
        salt = keccak256(abi.encode(sender, salt));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }

    /// @inheritdoc IContinuousClearingAuctionFactory
    function protocolFeeController() external view returns (IProtocolFeeController) {
        return PROTOCOL_FEE_CONTROLLER;
    }
}
