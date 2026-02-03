// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {BaseERC1155ValidationHook} from './BaseERC1155ValidationHook.sol';
import {IBaseERC1155ValidationHook} from './BaseERC1155ValidationHook.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';

interface IGatedERC1155ValidationHook is IBaseERC1155ValidationHook {
    /// @notice The block number until which the validation check is enforced
    function expirationBlock() external view returns (uint256);
}

/// @notice Validation hook for ERC1155 tokens that requires the sender to hold a specific token until a certain block number
/// @dev It is highly recommended to make the ERC1155 soulbound (non-transferable)
contract GatedERC1155ValidationHook is IGatedERC1155ValidationHook, BaseERC1155ValidationHook, BlockNumberish {
    /// @inheritdoc IGatedERC1155ValidationHook
    uint256 public immutable expirationBlock;

    constructor(address _erc1155, uint256 _tokenId, uint256 _expirationBlock)
        BaseERC1155ValidationHook(_erc1155, _tokenId)
    {
        expirationBlock = _expirationBlock;
    }

    /// @notice Require that the `owner` and `sender` of the bid hold at least one of the required ERC1155 token
    /// @dev This check is enforced until the `expirationBlock` block number
    /// @inheritdoc IValidationHook
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData)
        public
        view
        virtual
        override(BaseERC1155ValidationHook, IValidationHook)
    {
        if (_getBlockNumberish() < expirationBlock) {
            super.validate(maxPrice, amount, owner, sender, hookData);
        }
    }

    /// @dev Extend the existing introspection support to signal that derived contracts inherit from GatedERC1155ValidationHook
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(BaseERC1155ValidationHook, IERC165)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IGatedERC1155ValidationHook).interfaceId;
    }
}
