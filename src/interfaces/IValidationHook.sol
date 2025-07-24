// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid} from '../libraries/BidLib.sol';

interface IValidationHook {
    /// @notice Validate a bid
    /// @dev MUST revert if the bid is invalid
    /// @param bid The bid to validate
    /// @param hookData Additional data to pass to the hook required for validation
    function validate(Bid calldata bid, bytes calldata hookData) external view;
}
