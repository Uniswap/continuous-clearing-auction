// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAllowanceTransfer, PermitSingleForwarder} from 'twap-auction/PermitSingleForwarder.sol';

contract MockPermitSingleForwarder is PermitSingleForwarder {
    constructor(IAllowanceTransfer _permit2) PermitSingleForwarder(_permit2) {}
}
