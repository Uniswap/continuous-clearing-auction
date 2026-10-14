// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';

interface ISingletonGatedERC1155ValidationHook is IValidationHookIntrospection {
    /// @notice Gate settings for one auction
    /// @param tokenId The ERC1155 tokenId (ZKPassport policyId) that bidders must hold
    /// @param expirationBlock The block number until which the check is enforced
    /// @param registered True after `register` is called for the auction
    struct AuctionConfig {
        uint256 tokenId;
        uint64 expirationBlock;
        bool registered;
    }

    /// @notice Error thrown when the hook is deployed on a chain without the ZKPassport registry
    error UnsupportedChain();
    /// @notice Error thrown when `validate` is called by an auction that is not registered
    error AuctionNotRegistered(address auction);
    /// @notice Error thrown when the auction already has a config
    error AlreadyRegistered(address auction);
    /// @notice Error thrown when the auction has started
    error AuctionAlreadyStarted(address auction);
    /// @notice Error thrown when the sender is not the owner of the ERC1155 tokenId
    error NotOwnerOfERC1155Token(uint256 tokenId);
    /// @notice Error thrown when the sender is not the owner of the bid
    error SenderMustBeOwner();

    /// @notice Emitted when an auction is registered
    event AuctionRegistered(
        address indexed auction, address indexed registrant, uint256 tokenId, uint64 expirationBlock
    );

    /// @notice The ERC1155 contract that is checked for ownership (ZKPassport credentials registry)
    function erc1155() external view returns (IERC1155);

    /// @notice The gate settings for `auction`
    function configOf(address auction) external view returns (AuctionConfig memory);

    /// @notice Set the gate settings for `auction`. Permissionless, first write wins, and immutable after.
    /// @dev Front-run risk: anyone can register any auction address first, including a predicted address.
    ///      The launcher must deploy the auction and register it in the same transaction.
    ///      If the auction has code and exposes `startBlock()`, registration reverts at or after that block.
    function register(address auction, uint256 tokenId, uint64 expirationBlock) external;
}

/// @notice One validation hook for many auctions. Each auction has its own ZKPassport policyId (ERC1155 tokenId)
///         and expiration block. Until the expiration block, bidders must hold the credential and bid for themselves.
/// @dev The auction calls `validate`, so the config is read for `msg.sender`. An unregistered auction cannot take bids.
///      Credential expiry is handled by the registry: `balanceOf` returns 0 for an expired credential.
contract SingletonGatedERC1155ValidationHook is
    ISingletonGatedERC1155ValidationHook,
    ValidationHookIntrospection,
    BlockNumberish
{
    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    IERC1155 public immutable erc1155 = IERC1155(0x000C558ea450790ad88f4f15A302B8F2C9b60d6C);

    mapping(address auction => AuctionConfig) private _configOf;

    constructor() {
        if (block.chainid != 1 && block.chainid != 11_155_111) revert UnsupportedChain();
    }

    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    function configOf(address auction) external view returns (AuctionConfig memory) {
        return _configOf[auction];
    }

    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    function register(address auction, uint256 tokenId, uint64 expirationBlock) external {
        if (_configOf[auction].registered) revert AlreadyRegistered(auction);
        (bool success, bytes memory data) = auction.staticcall(abi.encodeWithSignature('startBlock()'));
        if (success && data.length >= 32 && _getBlockNumberish() >= abi.decode(data, (uint256))) {
            revert AuctionAlreadyStarted(auction);
        }
        _configOf[auction] = AuctionConfig(tokenId, expirationBlock, true);
        emit AuctionRegistered(auction, msg.sender, tokenId, expirationBlock);
    }

    /// @notice Require that the bid `owner` is the `sender` and holds the auction's ERC1155 tokenId
    /// @dev The check is enforced until the auction's `expirationBlock`
    /// @inheritdoc IValidationHook
    function validate(uint256, uint128, address owner, address sender, bytes calldata) external view {
        AuctionConfig memory config = _configOf[msg.sender];
        if (!config.registered) revert AuctionNotRegistered(msg.sender);
        if (_getBlockNumberish() >= config.expirationBlock) return;
        if (sender != owner) revert SenderMustBeOwner();
        if (erc1155.balanceOf(owner, config.tokenId) == 0) revert NotOwnerOfERC1155Token(config.tokenId);
    }

    /// @dev Extend the existing introspection support with ISingletonGatedERC1155ValidationHook
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ValidationHookIntrospection, IERC165)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId)
            || _interfaceId == type(ISingletonGatedERC1155ValidationHook).interfaceId;
    }
}
