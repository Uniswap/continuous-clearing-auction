// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {INotifier} from './interfaces/external/INotifier.sol';
import {ISubscriber} from './interfaces/external/ISubscriber.sol';

/// @title Notifier
/// @notice Abstract contract for notifying subscribers of the auction results
abstract contract Notifier is INotifier {
    ISubscriber[] public subscribers;

    uint64 public notifyBlock;

    constructor(ISubscriber[] memory _subscribers, uint64 _notifyBlock) {
        for (uint256 i = 0; i < _subscribers.length; i++) {
            if (address(_subscribers[i]) == address(0)) revert SubscriberIsZero();
            emit SubscriberRegistered(address(_subscribers[i]));
        }
        subscribers = _subscribers;
        notifyBlock = _notifyBlock;
    }

    /// @inheritdoc INotifier
    function notify() external virtual;

    /// @notice Notify the subscribers of the auction results
    /// @param priceX192 The price in 192-bit fixed point format
    /// @param tokenAmount The amount of tokens to match with the currency raised at the price
    /// @param currencyAmount The amount of currency raised
    function _notify(uint256 priceX192, uint128 tokenAmount, uint128 currencyAmount) internal {
        for (uint256 i = 0; i < subscribers.length; i++) {
            subscribers[i].setInitialPrice(priceX192, tokenAmount, currencyAmount);
        }
    }
}
