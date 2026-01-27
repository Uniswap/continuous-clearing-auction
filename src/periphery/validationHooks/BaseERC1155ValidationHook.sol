// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

interface IBaseERC1155ValidationHook is IValidationHookIntrospection {
    /// @notice The ERC1155 token contract that is checked for ownership
    /// @dev Callers should query the returned interface's `balanceOf` method
    function erc1155() external view returns (IERC1155);
    /// @notice The ERC1155 tokenId that is checked for ownership
    function tokenId() external view returns (uint256);
}

/// @notice Base validation hook for ERC1155 tokens
/// @dev This hook validates that the sender is the owner of a specific ERC1155 tokenId
///      It is highly recommended to make the ERC1155 soulbound (non-transferable)
contract BaseERC1155ValidationHook is IBaseERC1155ValidationHook, ValidationHookIntrospection {
    /// @inheritdoc IBaseERC1155ValidationHook
    IERC1155 public immutable erc1155;
    /// @inheritdoc IBaseERC1155ValidationHook
    uint256 public immutable tokenId;

    /// @notice Error thrown when the token address is invalid
    error InvalidTokenAddress();
    /// @notice Error thrown when the sender is not the owner of the ERC1155 tokenId
    error NotOwnerOfERC1155Token(uint256 tokenId);
    /// @notice Error thrown when the sender is not the owner of the ERC1155 token
    error SenderMustBeOwner();

    /// @notice Emitted when the ERC1155 tokenId is set
    /// @param tokenAddress The address of the ERC1155 token
    /// @param tokenId The ID of the ERC1155 token
    event ERC1155TokenIdSet(address indexed tokenAddress, uint256 tokenId);

    constructor(address _erc1155, uint256 _tokenId) {
        if (_erc1155 == address(0)) revert InvalidTokenAddress();
        erc1155 = IERC1155(_erc1155);
        tokenId = _tokenId;
        emit ERC1155TokenIdSet(_erc1155, tokenId);
    }

    /// @notice Require that the `owner` and `sender` of the bid hold at least one of the required ERC1155 token
    /// @inheritdoc IValidationHook
    function validate(uint256, uint128, address owner, address sender, bytes calldata) public view virtual {
        if (sender != owner) revert SenderMustBeOwner();
        if (erc1155.balanceOf(owner, tokenId) == 0) revert NotOwnerOfERC1155Token(tokenId);
    }

    /// @dev Extend the existing introspection support to signal that derived contracts inherit from BaseERC1155ValidationHook
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ValidationHookIntrospection, IERC165)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IBaseERC1155ValidationHook).interfaceId;
    }
}
