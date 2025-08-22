// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISubscriber} from '../../src/interfaces/external/ISubscriber.sol';

/// @title MockSubscriber
/// @notice Mock implementation of the ISubscriber contract
contract MockSubscriber is ISubscriber {
    /// @inheritdoc ISubscriber
    function setInitialPrice(uint256 priceX192, uint128 tokenAmount, uint128 currencyAmount) external payable {
        emit InitialPriceSet(priceX192, tokenAmount, currencyAmount);
    }
}
