// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {Test} from 'forge-std/Test.sol';
import {MockERC1155} from 'lib/solady/test/utils/mocks/MockERC1155.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {
    ISingletonGatedERC1155ValidationHook,
    SingletonGatedERC1155ValidationHook
} from 'src/periphery/validationHooks/SingletonGatedERC1155ValidationHook.sol';

contract MockStartBlockAuction {
    uint64 public startBlock;

    constructor(uint64 _startBlock) {
        startBlock = _startBlock;
    }
}

contract SingletonGatedERC1155ValidationHookTest is Test {
    address constant REGISTRY = 0x000C558ea450790ad88f4f15A302B8F2C9b60d6C;
    uint256 constant POLICY_ID = 7;

    SingletonGatedERC1155ValidationHook hook;
    MockERC1155 registry;
    address auction = makeAddr('auction');
    address bidder = makeAddr('bidder');

    function setUp() public {
        vm.chainId(1);
        vm.etch(REGISTRY, address(new MockERC1155()).code);
        registry = MockERC1155(REGISTRY);
        hook = new SingletonGatedERC1155ValidationHook();
    }

    function _validate(address owner, address sender) internal {
        vm.prank(auction);
        hook.validate(0, 0, owner, sender, '');
    }

    function test_constructor_onUnsupportedChain_reverts() public {
        vm.chainId(10);
        vm.expectRevert(ISingletonGatedERC1155ValidationHook.UnsupportedChain.selector);
        new SingletonGatedERC1155ValidationHook();
    }

    function test_constructor_onSepolia_succeeds() public {
        vm.chainId(11_155_111);
        new SingletonGatedERC1155ValidationHook();
    }

    function test_erc1155_isRegistry() public view {
        assertEq(address(hook.erc1155()), REGISTRY);
    }

    function test_supportsInterface() public view {
        assertTrue(hook.supportsInterface(type(IERC165).interfaceId));
        assertTrue(hook.supportsInterface(type(IValidationHook).interfaceId));
        assertTrue(hook.supportsInterface(type(ISingletonGatedERC1155ValidationHook).interfaceId));
        assertFalse(hook.supportsInterface(bytes4(keccak256('not_supported'))));
    }

    function test_register_storesConfigAndEmits(uint256 tokenId, uint64 expirationBlock) public {
        address registrant = makeAddr('registrant');
        vm.expectEmit(address(hook));
        emit ISingletonGatedERC1155ValidationHook.AuctionRegistered(auction, registrant, tokenId, expirationBlock);
        vm.prank(registrant);
        hook.register(auction, tokenId, expirationBlock);
        ISingletonGatedERC1155ValidationHook.AuctionConfig memory config = hook.configOf(auction);
        assertEq(config.tokenId, tokenId);
        assertEq(config.expirationBlock, expirationBlock);
        assertTrue(config.registered);
    }

    function test_register_twice_reverts() public {
        hook.register(auction, POLICY_ID, 100);
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AlreadyRegistered.selector, auction)
        );
        vm.prank(makeAddr('attacker'));
        hook.register(auction, POLICY_ID + 1, 0);
    }

    function test_register_beforeStartBlock_succeeds() public {
        address started = address(new MockStartBlockAuction(uint64(block.number + 1)));
        hook.register(started, POLICY_ID, 100);
        assertTrue(hook.configOf(started).registered);
    }

    function test_register_atOrAfterStartBlock_reverts(uint64 startBlock) public {
        vm.assume(startBlock > 0);
        address started = address(new MockStartBlockAuction(startBlock));
        vm.roll(startBlock);
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AuctionAlreadyStarted.selector, started)
        );
        hook.register(started, POLICY_ID, 100);
    }

    function test_validate_whenNotRegistered_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AuctionNotRegistered.selector, auction)
        );
        _validate(bidder, bidder);
    }

    function test_validate_whenRegisteredForOtherAuction_reverts() public {
        hook.register(makeAddr('other'), POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID, 1, '');
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AuctionNotRegistered.selector, auction)
        );
        _validate(bidder, bidder);
    }

    function test_validate_whenSenderIsNotOwner_reverts() public {
        hook.register(auction, POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID, 1, '');
        vm.expectRevert(ISingletonGatedERC1155ValidationHook.SenderMustBeOwner.selector);
        _validate(bidder, makeAddr('router'));
    }

    function test_validate_whenNoCredential_reverts() public {
        hook.register(auction, POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID + 1, 1, '');
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.NotOwnerOfERC1155Token.selector, POLICY_ID)
        );
        _validate(bidder, bidder);
    }

    function test_validate_whenCredentialHeld_succeeds() public {
        hook.register(auction, POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID, 1, '');
        _validate(bidder, bidder);
    }

    function test_validate_atOrAfterExpirationBlock_skipsCheck(uint64 expirationBlock, uint64 blockNumber) public {
        vm.assume(blockNumber >= expirationBlock);
        hook.register(auction, POLICY_ID, expirationBlock);
        vm.roll(blockNumber);
        _validate(bidder, makeAddr('router'));
    }

    function test_validate_usesEachAuctionsPolicy() public {
        address auctionB = makeAddr('auctionB');
        hook.register(auction, POLICY_ID, type(uint64).max);
        hook.register(auctionB, POLICY_ID + 1, type(uint64).max);
        registry.mint(bidder, POLICY_ID, 1, '');
        _validate(bidder, bidder);
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.NotOwnerOfERC1155Token.selector, POLICY_ID + 1)
        );
        vm.prank(auctionB);
        hook.validate(0, 0, bidder, bidder, '');
    }
}
