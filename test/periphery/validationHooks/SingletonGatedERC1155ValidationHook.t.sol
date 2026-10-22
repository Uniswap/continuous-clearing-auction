// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {Test} from 'forge-std/Test.sol';
import {MockERC1155} from 'lib/solady/test/utils/mocks/MockERC1155.sol';
import {IDistributor} from 'liquidity-launcher/src/interfaces/IDistributor.sol';
import {ContinuousClearingAuctionFactory} from 'src/ContinuousClearingAuctionFactory.sol';
import {AuctionParameters, IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {
    IBaseERC1155ValidationHook,
    IERC1155ValidationErrors
} from 'src/periphery/validationHooks/BaseERC1155ValidationHook.sol';
import {IGatedERC1155ValidationHook} from 'src/periphery/validationHooks/GatedERC1155ValidationHook.sol';
import {
    ISingletonGatedERC1155ValidationHook,
    SingletonGatedERC1155ValidationHook
} from 'src/periphery/validationHooks/SingletonGatedERC1155ValidationHook.sol';
import {AuctionParamsBuilder} from 'test/utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from 'test/utils/AuctionStepsBuilder.sol';
import {MockToken} from 'test/utils/MockToken.sol';

contract MockDeployedAuction {
    address public immutable validationHook;
    uint64 public immutable startBlock;

    constructor(address _validationHook, uint64 _startBlock) {
        validationHook = _validationHook;
        startBlock = _startBlock;
    }
}

contract MockRevertingStartBlockAuction {
    address public immutable validationHook;

    error StartBlockReverted();

    constructor(address _validationHook) {
        validationHook = _validationHook;
    }

    function startBlock() external pure returns (uint64) {
        revert StartBlockReverted();
    }
}

contract SingletonGatedERC1155ValidationHookTest is Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    uint256 constant POLICY_ID = 7;
    uint256 constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    uint128 constant TOTAL_SUPPLY = 1000e18;
    uint24 constant MPS_PER_BLOCK = 100_000;
    uint40 constant STEP_BLOCKS = 100;

    SingletonGatedERC1155ValidationHook hook;
    MockERC1155 registry;
    address auction = makeAddr('auction');
    address bidder = makeAddr('bidder');

    function setUp() public {
        registry = new MockERC1155();
        hook = new SingletonGatedERC1155ValidationHook(address(registry));
    }

    function _validate(address owner, address sender) internal {
        vm.prank(auction);
        hook.validate(0, 0, owner, sender, '');
    }

    function _futureExpiration() internal view returns (uint64) {
        return uint64(block.number + 1);
    }

    function test_constructor_whenErc1155IsZeroAddress_reverts() public {
        vm.expectRevert(IERC1155ValidationErrors.InvalidTokenAddress.selector);
        new SingletonGatedERC1155ValidationHook(address(0));
    }

    function test_supportsInterface() public view {
        assertTrue(hook.supportsInterface(type(IERC165).interfaceId));
        assertTrue(hook.supportsInterface(type(IValidationHook).interfaceId));
        assertTrue(hook.supportsInterface(type(ISingletonGatedERC1155ValidationHook).interfaceId));
        assertFalse(hook.supportsInterface(type(IBaseERC1155ValidationHook).interfaceId));
        assertFalse(hook.supportsInterface(type(IGatedERC1155ValidationHook).interfaceId));
        assertFalse(hook.supportsInterface(bytes4(keccak256('not_supported'))));
    }

    function test_register_storesConfigAndEmits(uint256 tokenId, uint64 expirationBlock) public {
        vm.assume(expirationBlock > block.number);
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
        hook.register(auction, POLICY_ID, _futureExpiration());
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AlreadyRegistered.selector, auction)
        );
        vm.prank(makeAddr('attacker'));
        hook.register(auction, POLICY_ID + 1, 0);
    }

    function test_register_predictedAddressWithNoCode_succeeds() public {
        address predicted = makeAddr('predicted');
        assertEq(predicted.code.length, 0);
        hook.register(predicted, POLICY_ID, _futureExpiration());
        assertTrue(hook.configOf(predicted).registered);
        assertEq(hook.configOf(predicted).tokenId, POLICY_ID);
    }

    function test_register_beforeStartBlock_succeeds() public {
        uint64 startBlock = uint64(block.number + 1);
        address started = address(new MockDeployedAuction(address(hook), startBlock));
        hook.register(started, POLICY_ID, _futureExpiration());
        assertTrue(hook.configOf(started).registered);
    }

    function test_register_atOrAfterStartBlock_reverts(uint64 startBlock, uint64 blockNumber) public {
        vm.assume(blockNumber >= startBlock);
        vm.assume(blockNumber < type(uint64).max);
        vm.roll(blockNumber);
        address started = address(new MockDeployedAuction(address(hook), startBlock));
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AuctionAlreadyStarted.selector, started)
        );
        hook.register(started, POLICY_ID, uint64(blockNumber + 1));
    }

    function test_register_whenStartBlockReverts_reverts() public {
        MockRevertingStartBlockAuction started = new MockRevertingStartBlockAuction(address(hook));
        vm.expectRevert(MockRevertingStartBlockAuction.StartBlockReverted.selector);
        hook.register(address(started), POLICY_ID, _futureExpiration());
    }

    function test_register_whenExpirationBlockIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.ExpirationBlockNotInFuture.selector, uint64(0))
        );
        hook.register(auction, POLICY_ID, 0);
    }

    function test_register_whenExpirationBlockIsInThePast_reverts(uint64 expirationBlock) public {
        vm.assume(expirationBlock > 0);
        vm.assume(expirationBlock < type(uint64).max);
        vm.roll(uint256(expirationBlock) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingletonGatedERC1155ValidationHook.ExpirationBlockNotInFuture.selector, expirationBlock
            )
        );
        hook.register(auction, POLICY_ID, expirationBlock);
    }

    function test_register_whenExpirationBlockEqualsCurrentBlock_reverts(uint64 blockNumber) public {
        vm.roll(blockNumber);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingletonGatedERC1155ValidationHook.ExpirationBlockNotInFuture.selector, blockNumber
            )
        );
        hook.register(auction, POLICY_ID, blockNumber);
    }

    function test_register_whenDeployedAuctionHasWrongHook_reverts(address otherHook) public {
        vm.assume(otherHook != address(hook));
        address started = address(new MockDeployedAuction(otherHook, uint64(block.number + 10)));
        vm.expectRevert(
            abi.encodeWithSelector(ISingletonGatedERC1155ValidationHook.AuctionValidationHookMismatch.selector, started)
        );
        hook.register(started, POLICY_ID, _futureExpiration());
    }

    function test_register_beforeFactoryCreate_succeeds() public {
        ContinuousClearingAuctionFactory factory = new ContinuousClearingAuctionFactory(address(0));
        MockToken token = new MockToken();
        address tokensRecipient = makeAddr('tokensRecipient');
        address fundsRecipient = makeAddr('fundsRecipient');
        bytes memory steps = AuctionStepsBuilder.init().addStep(MPS_PER_BLOCK, STEP_BLOCKS);
        // startBlock is the current block, so the deployed-auction guard would reject this address.
        // Registration happens first, while the predicted address still has no code.
        AuctionParameters memory params = AuctionParamsBuilder.init()
            .withCurrency(address(0))
            .withFloorPrice(FLOOR_PRICE)
            .withTickSpacing(TICK_SPACING)
            .withValidationHook(address(hook))
            .withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number)
            .withEndBlock(block.number + STEP_BLOCKS)
            .withClaimBlock(block.number + STEP_BLOCKS)
            .withAuctionStepsData(steps);

        bytes memory configData = abi.encode(params);
        bytes32 salt = keccak256('singleton-hook');
        address sender = makeAddr('launcher');
        address predicted = address(factory.getAddress(address(token), TOTAL_SUPPLY, configData, salt, sender));
        assertEq(predicted.code.length, 0);

        uint64 expirationBlock = uint64(block.number + STEP_BLOCKS);
        hook.register(predicted, POLICY_ID, expirationBlock);

        vm.prank(sender);
        IDistributor distributor = factory.create(address(token), TOTAL_SUPPLY, configData, salt);
        assertEq(address(distributor), predicted);
        assertGt(predicted.code.length, 0);
        assertEq(address(IContinuousClearingAuction(predicted).validationHook()), address(hook));

        ISingletonGatedERC1155ValidationHook.AuctionConfig memory config = hook.configOf(predicted);
        assertTrue(config.registered);
        assertEq(config.tokenId, POLICY_ID);
        assertEq(config.expirationBlock, expirationBlock);
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
        vm.expectRevert(IERC1155ValidationErrors.SenderMustBeOwner.selector);
        _validate(bidder, makeAddr('router'));
    }

    function test_validate_whenNoCredential_reverts() public {
        hook.register(auction, POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID + 1, 1, '');
        vm.expectRevert(abi.encodeWithSelector(IERC1155ValidationErrors.NotOwnerOfERC1155Token.selector, POLICY_ID));
        _validate(bidder, bidder);
    }

    function test_validate_whenCredentialHeld_succeeds() public {
        hook.register(auction, POLICY_ID, type(uint64).max);
        registry.mint(bidder, POLICY_ID, 1, '');
        _validate(bidder, bidder);
    }

    function test_validate_atOrAfterExpirationBlock_skipsCheck(uint64 expirationBlock, uint64 blockNumber) public {
        vm.assume(expirationBlock > block.number);
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
        vm.expectRevert(abi.encodeWithSelector(IERC1155ValidationErrors.NotOwnerOfERC1155Token.selector, POLICY_ID + 1));
        vm.prank(auctionB);
        hook.validate(0, 0, bidder, bidder, '');
    }
}
