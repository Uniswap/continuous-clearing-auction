// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';

contract MockPermit2 {
    bool public shouldRevert;
    bytes public lastReason;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setLastReason(bytes memory _reason) external {
        lastReason = _reason;
    }

    function permit(address, IAllowanceTransfer.PermitSingle calldata, bytes calldata) external view {
        if (shouldRevert) {
            revert(string(lastReason));
        }
    }
}