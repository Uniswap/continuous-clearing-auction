// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Auction} from './Auction.sol';
import {AuctionParameters} from './interfaces/IAuction.sol';
import {IAuctionFactory} from './interfaces/IAuctionFactory.sol';
import {IDistributionStrategy} from './interfaces/external/IDistributionStrategy.sol';
import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';

/// @title AuctionFactory
contract AuctionFactory is IAuctionFactory {
    /// @dev Get the create2 address for the auction
    function _getCreate2Address(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        internal
        view
        returns (address)
    {
        AuctionParameters memory parameters = abi.decode(configData, (AuctionParameters));
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(Auction).creationCode, abi.encode(token, amount, parameters)));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }

    /// @inheritdoc IDistributionStrategy
    function getAddressesAndAmounts(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addresses[0] = _getCreate2Address(token, amount, configData, salt);
        amounts[0] = amount;
        return (addresses, amounts);
    }

    /// @inheritdoc IDistributionStrategy
    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt) external {
        address auction = address(new Auction{salt: salt}(token, amount, abi.decode(configData, (AuctionParameters))));

        emit AuctionCreated(auction, token, amount, configData);
    }
}
