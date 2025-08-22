// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INotifier {
    /// @notice Error thrown when the subscriber is the zero address
    error SubscriberIsZero();

    /// @notice Error thrown before notifyBlock
    error CannotNotifyYet();

    /// @notice Emitted when a subscriber is registered
    /// @param subscriber The address of the subscriber
    event SubscriberRegistered(address indexed subscriber);

    /// @notice Notify the subscribers
    /// @dev The schema is defined by the implementation, proper authorization checks must be done
    function notify() external;
}
