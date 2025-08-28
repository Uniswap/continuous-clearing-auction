// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title MockFundsRecipient
/// @notice A mock implementation of the funds recipient
contract MockFundsRecipient {
    event RevertWithReason(bytes reason);
    event RevertWithoutReason();

    function revertWithReason(bytes memory reason) external pure {
        revert(string(reason));
    }

    function revertWithoutReason() external pure {
        revert();
    }

    receive() external payable {}

    // All other calls are successful
    fallback() external {}
}
