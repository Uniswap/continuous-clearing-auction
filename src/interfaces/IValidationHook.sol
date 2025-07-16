// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid} from '../libraries/BidLib.sol';

interface IValidationHook {
    /// @notice Validate a bid
    /// @dev MUST revert if the bid is invalid
    function validate(Bid calldata bid) external view;
}