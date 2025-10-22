// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../interfaces/IValidationHook.sol';

/// @title ValidationHookLib
/// @notice Library for handling calls to validation hooks and bubbling up the revert reason
library ValidationHookLib {
    /// @notice Error thrown when a validation hook call fails
    /// @param reason The bubbled up revert reason
    error ValidationHookCallFailed(bytes reason);

    /// @notice Handles calling a validation hook and bubbling up the revert reason
    function handleValidate(
        IValidationHook hook,
        uint256 maxPrice,
        uint128 amount,
        address owner,
        address sender,
        bytes calldata hookData
    ) internal {
        if (address(hook) == address(0)) return;

        (bool success, bytes memory reason) = address(hook)
            .call(abi.encodeWithSelector(IValidationHook.validate.selector, maxPrice, amount, owner, sender, hookData));
        if (!success) revert ValidationHookCallFailed(reason);
    }
}
