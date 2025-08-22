// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Notifier} from '../../src/Notifier.sol';
import {ISubscriber} from '../../src/interfaces/external/ISubscriber.sol';

/// @title MockNotifier
/// @notice Mock implementation of the Notifier contract
contract MockNotifier is Notifier {
    uint256 public priceX192;
    uint128 public tokenAmount;
    uint128 public currencyAmount;

    constructor(ISubscriber[] memory _subscribers, uint64 _notifyBlock) Notifier(_subscribers, _notifyBlock) {}

    /// @notice Set the priceX192 for testing
    function setPriceX192(uint256 _priceX192) external {
        priceX192 = _priceX192;
    }

    /// @notice Set the tokenAmount for testing
    function setTokenAmount(uint128 _tokenAmount) external {
        tokenAmount = _tokenAmount;
    }

    /// @notice Set the currencyAmount for testing
    function setCurrencyAmount(uint128 _currencyAmount) external {
        currencyAmount = _currencyAmount;
    }

    /// @inheritdoc Notifier
    function notify() external override {
        _notify(priceX192, tokenAmount, currencyAmount);
    }
}
