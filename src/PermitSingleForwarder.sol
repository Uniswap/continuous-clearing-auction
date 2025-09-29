// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAllowanceTransfer, IPermitSingleForwarder} from './interfaces/IPermitSingleForwarder.sol';

/// @notice PermitSingleForwarder allows permitting this contract as a spender on permit2
/// @dev This contract does not enforce the spender to be this contract, but that is the intended use case
abstract contract PermitSingleForwarder is IPermitSingleForwarder {
    /// @notice Permit2 address
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @notice the Permit2 contract to forward approvals
    IAllowanceTransfer public immutable permit2;

    constructor(IAllowanceTransfer _permit2) {
        permit2 = _permit2;
    }

    /// @inheritdoc IPermitSingleForwarder
    function permit(address owner, IAllowanceTransfer.PermitSingle calldata permitSingle, bytes calldata signature)
        external
        payable
        returns (bytes memory err)
    {
        // use try/catch in case an actor front-runs the permit, which would DOS multicalls
        try permit2.permit(owner, permitSingle, signature) {}
        catch (bytes memory reason) {
            err = reason;
        }
    }
}
