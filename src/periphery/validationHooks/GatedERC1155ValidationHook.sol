// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {BaseERC1155ValidationHook} from './BaseERC1155ValidationHook.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';

/// @notice Validation hook for ERC1155 tokens that requires the sender to hold a specific token until a certain block number
/// @dev It is highly recommended to make the ERC1155 soulbound (non-transferable)
contract GatedERC1155ValidationHook is BaseERC1155ValidationHook, BlockNumberish {
    /// @notice The block number until which the validation check is enforced
    uint256 public immutable gateUntil;

    constructor(address _erc1155, uint256 _tokenId, uint256 _gateUntil) BaseERC1155ValidationHook(_erc1155, _tokenId) {
        gateUntil = _gateUntil;
    }

    /// @notice Require that the `owner` and `sender` of the bid hold at least one of the required ERC1155 token
    /// @dev This check is enforced until the `gateUntil` block number
    /// @inheritdoc IValidationHook
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
        public
        view
        override
    {
        if (_getBlockNumberish() < gateUntil) {
            super.validate(maxPrice, amount, owner, sender, hookData);
        }
    }
}
