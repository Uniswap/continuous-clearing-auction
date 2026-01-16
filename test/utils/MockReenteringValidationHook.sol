// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';

/// @notice Mock validation hook that reenters the auction when the attacker's address is the sender
contract MockReenteringValidationHook is IValidationHook {
    address private immutable _attacker;

    constructor(address attacker_) {
        _attacker = attacker_;
    }

    function validate(uint256, uint128, address, address sender, bytes calldata) external override {
        if (sender == _attacker) {
            ContinuousClearingAuction(msg.sender).forceIterateOverTicks(type(uint256).max);
        }
    }
}
