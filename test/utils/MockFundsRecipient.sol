// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title MockFundsRecipient
/// @notice A mock implementation of the funds recipient
contract MockFundsRecipient {
    event RevertWithReason(bytes reason);
    event RevertWithoutReason();

    function revertWithReason(bytes memory reason) external {
        revert(string(reason));
    }

    function revertWithoutReason() external {
        revert();
    }

    // All other calls are successful, as well as receiving ETH
    fallback() external payable {}
}