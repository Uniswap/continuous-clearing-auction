// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../../interfaces/IContinuousClearingAuction.sol';
import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IERC1155ValidationErrors} from './BaseERC1155ValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';

interface ISingletonGatedERC1155ValidationHook is IValidationHookIntrospection, IERC1155ValidationErrors {
    /// @notice Gate settings for one auction
    /// @param tokenId The ERC1155 tokenId (ZKPassport policyId) that bidders must hold
    /// @param expirationBlock The block number until which the check is enforced
    /// @param registered True after `register` is called for the auction
    struct AuctionConfig {
        uint256 tokenId;
        uint64 expirationBlock;
        bool registered;
    }

    /// @notice Error thrown when `validate` is called by an auction that is not registered
    error AuctionNotRegistered(address auction);
    /// @notice Error thrown when the auction already has a config
    error AlreadyRegistered(address auction);
    /// @notice Error thrown when a deployed auction does not use this hook
    error AuctionValidationHookMismatch(address auction);
    /// @notice Error thrown when the auction has started
    error AuctionAlreadyStarted(address auction);
    /// @notice Error thrown when `expirationBlock` is at or before the current block
    error ExpirationBlockNotInFuture(uint64 expirationBlock);

    /// @notice Emitted when an auction is registered
    /// @param auction The auction that was registered
    /// @param registrant The account that registered the auction
    /// @param tokenId The ERC1155 tokenId (ZKPassport policyId) that bidders must hold
    /// @param expirationBlock The block number until which the check is enforced
    event AuctionRegistered(
        address indexed auction, address indexed registrant, uint256 tokenId, uint64 expirationBlock
    );

    /// @notice The ERC1155 contract that is checked for ownership (ZKPassport credentials registry)
    function erc1155() external view returns (IERC1155);

    /// @notice The gate settings for `auction`
    function configOf(address auction) external view returns (AuctionConfig memory);

    /// @notice Set the gate settings for `auction`. Permissionless, first write wins, and immutable after.
    /// @dev Register before calling `ContinuousClearingAuctionFactory.create`. Squatting a predicted address is an
    ///      accepted risk. A squatted salt can be avoided by using a new salt.
    ///      The `startBlock` check applies only to auctions that are already deployed. Those auctions must use this
    ///      hook (`validationHook() == address(this)`) and registration reverts at or after `startBlock`.
    /// @param auction The auction address. It may be a predicted address with no code.
    /// @param tokenId The ERC1155 tokenId (ZKPassport policyId) that bidders must hold
    /// @param expirationBlock The block until which the check is enforced. Must be after the current block.
    function register(address auction, uint256 tokenId, uint64 expirationBlock) external;
}

/// @notice One validation hook for many auctions. Each auction has its own ZKPassport policyId (ERC1155 tokenId)
///         and expiration block. Until the expiration block, bidders must hold the credential and bid for themselves.
/// @dev The auction calls `validate`, so the config is read for `msg.sender`. An unregistered auction cannot take bids.
///      Credential expiry is handled by the registry: `balanceOf` returns 0 for an expired credential.
///      This hook does not claim the `IBaseERC1155ValidationHook` or `IGatedERC1155ValidationHook` interface IDs.
contract SingletonGatedERC1155ValidationHook is
    ISingletonGatedERC1155ValidationHook,
    ValidationHookIntrospection,
    BlockNumberish
{
    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    IERC1155 public immutable erc1155;

    mapping(address auction => AuctionConfig) private _configOf;

    /// @param _erc1155 The ERC1155 registry checked for credential ownership
    constructor(address _erc1155) {
        if (_erc1155 == address(0)) revert InvalidTokenAddress();
        erc1155 = IERC1155(_erc1155);
    }

    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    function configOf(address auction) external view returns (AuctionConfig memory) {
        return _configOf[auction];
    }

    /// @inheritdoc ISingletonGatedERC1155ValidationHook
    function register(address auction, uint256 tokenId, uint64 expirationBlock) external {
        if (_configOf[auction].registered) revert AlreadyRegistered(auction);
        if (expirationBlock <= _getBlockNumberish()) revert ExpirationBlockNotInFuture(expirationBlock);
        // Deployed auctions only. Predicted addresses have no code and are registered before `factory.create`.
        if (auction.code.length > 0) {
            if (address(IContinuousClearingAuction(auction).validationHook()) != address(this)) {
                revert AuctionValidationHookMismatch(auction);
            }
            if (_getBlockNumberish() >= IContinuousClearingAuction(auction).startBlock()) {
                revert AuctionAlreadyStarted(auction);
            }
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

    /// @dev Extend the existing introspection support with ISingletonGatedERC1155ValidationHook.
    ///      `IBaseERC1155ValidationHook` and `IGatedERC1155ValidationHook` are intentionally not claimed.
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
