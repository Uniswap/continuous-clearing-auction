// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IERC1155} from 'openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol';

/// @notice Base validation hook for ERC1155 tokens
/// @dev This hook validates that the sender is the owner of a specific ERC1155 tokenId
///      It is highly recommended to make the ERC1155 soulbound (non-transferable)
contract BaseERC1155ValidationHook is IValidationHook {
    IERC1155 public immutable erc1155;
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
}
