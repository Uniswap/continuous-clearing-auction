// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from './ContinuousClearingAuction.sol';
import {AuctionParameters} from './interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from './interfaces/IContinuousClearingAuctionFactory.sol';
import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {IDistributor} from 'liquidity-launcher/src/interfaces/IDistributor.sol';
import {IDistributorFactory} from 'liquidity-launcher/src/interfaces/IDistributorFactory.sol';
import {IProtocolFeeController} from 'liquidity-launcher/src/interfaces/IProtocolFeeController.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';

/// @title ContinuousClearingAuctionFactory
/// @notice Deploy a new factory to use a different protocol fee controller for newly created auctions.
/// @custom:security-contact security@uniswap.org
contract ContinuousClearingAuctionFactory is IContinuousClearingAuctionFactory {
    /// @notice The protocol fee controller to use for all created auctions
    IProtocolFeeController internal immutable PROTOCOL_FEE_CONTROLLER;

    constructor(address _protocolFeeController) {
        PROTOCOL_FEE_CONTROLLER = IProtocolFeeController(_protocolFeeController);
    }

    /// @inheritdoc IDistributorFactory
    function create(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributor distributor)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);

        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the msg.sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = msg.sender;
        // If the fundsRecipient is address(1), set it to the msg.sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = msg.sender;

        distributor = IDistributor(
            address(
                new ContinuousClearingAuction{salt: keccak256(abi.encode(msg.sender, salt))}(
                    token, uint128(amount), parameters, address(PROTOCOL_FEE_CONTROLLER)
                )
            )
        );

        emit AuctionCreated(address(distributor), token, uint128(amount), abi.encode(parameters));
    }

    /// @inheritdoc IDistributorFactory
    function getAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
        external
        view
        returns (IDistributor distributor)
    {
        if (amount > type(uint128).max) revert InvalidTokenAmount(amount);
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        // If the tokensRecipient is address(1), set it to the sender
        if (parameters.tokensRecipient == ActionConstants.MSG_SENDER) parameters.tokensRecipient = sender;
        // If the fundsRecipient is address(1), set it to the sender
        if (parameters.fundsRecipient == ActionConstants.MSG_SENDER) parameters.fundsRecipient = sender;

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(ContinuousClearingAuction).creationCode,
                abi.encode(token, uint128(amount), parameters, address(PROTOCOL_FEE_CONTROLLER))
            )
        );
        distributor =
            IDistributor(Create2.computeAddress(keccak256(abi.encode(sender, salt)), initCodeHash, address(this)));
    }

    /// @inheritdoc IContinuousClearingAuctionFactory
    function protocolFeeController() external view returns (IProtocolFeeController) {
        return PROTOCOL_FEE_CONTROLLER;
    }
}
