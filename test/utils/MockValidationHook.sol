// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';

contract MockValidationHook is IValidationHook {
    /// @notice Validate a bid - this mock always passes validation
    /// @param maxPrice The maximum price the bidder is willing to pay
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param sender The sender of the bid
    /// @param hookData Additional data to pass to the hook required for validation
    function validate(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        address sender,
        bytes calldata hookData
    ) external pure {
        // This mock always passes validation - no requirements
        // Just return without any checks to ensure it doesn't revert
    }
}
