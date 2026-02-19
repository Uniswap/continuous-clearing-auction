// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {Clones} from 'openzeppelin-contracts/contracts/proxy/Clones.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {IModularValidationHook, Module, ModuleHookData} from 'src/interfaces/periphery/IModularValidationHook.sol';
import {ModularValidationHook, ModuleLib} from 'src/periphery/validationHooks/ModularValidationHook.sol';
import {
    MockRevertingValidationHook,
    MockRevertingValidationHookErrorWithString,
    MockRevertingValidationHookWithCustomError
} from 'test/utils/MockRevertingValidationHook.sol';
import {MockValidationHook} from 'test/utils/MockValidationHook.sol';
import {CustomRevert} from 'v4-core/libraries/CustomRevert.sol';

contract ModularValidationHookTest is Test {
    using ModuleLib for Module;

    address owner = makeAddr('owner');
    address sender = makeAddr('sender');

    // From openzeppelin-contracts/contracts/proxy/Clones.sol
    error FailedDeployment();

    ModularValidationHook impl;

    MockValidationHook mockHook;
    MockRevertingValidationHook revertingHook;
    MockRevertingValidationHookWithCustomError revertingHookWithCustomError;
    MockRevertingValidationHookErrorWithString revertingHookWithString;

    modifier givenValidModuleId(Module memory module) {
        // From solady/src/utils/EnumerableSetLib.sol
        vm.assume(module.toId() != uint72(bytes9(keccak256(bytes('_ZERO_SENTINEL')))));
        vm.assume(address(module.hook) != address(this));
        _;
    }

    function setUp() public {
        impl = new ModularValidationHook();
        mockHook = new MockValidationHook();
        revertingHook = new MockRevertingValidationHook();
        revertingHookWithCustomError = new MockRevertingValidationHookWithCustomError();
        revertingHookWithString = new MockRevertingValidationHookErrorWithString();
    }

    function _deploy(Module[] memory _modules) internal returns (ModularValidationHook) {
        ModularValidationHook clone = ModularValidationHook(Clones.cloneDeterministic(address(impl), bytes32(0)));
        clone.initialize(_modules);
        return clone;
    }

    function _toBytesArray(bytes memory _data) internal pure returns (bytes[] memory wrapped) {
        wrapped = new bytes[](1);
        wrapped[0] = _data;
    }

    function test_constructor_revertsWhenHookIsZero() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(address(0))});
        ModularValidationHook clone = ModularValidationHook(Clones.cloneDeterministic(address(impl), bytes32(0)));
        vm.expectRevert(abi.encodeWithSelector(IModularValidationHook.InvalidModuleHook.selector));
        clone.initialize(modules);
    }

    function test_constructor_revertsWhenModuleIsAlreadySet() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: true, allowRevert: true, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: true, allowRevert: true, hook: IValidationHook(mockHook)});
        ModularValidationHook clone = ModularValidationHook(Clones.cloneDeterministic(address(impl), bytes32(0)));
        vm.expectRevert(abi.encodeWithSelector(IModularValidationHook.ModuleAlreadySet.selector, modules[0].toId()));
        clone.initialize(modules);
    }

    function test_moduleIdsAndModules_areSet() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: true, allowRevert: true, hook: IValidationHook(mockHook)});
        vm.expectEmit(true, true, true, true);
        emit IModularValidationHook.ModuleSet(modules[0].toId(), IValidationHook(mockHook), false, false);
        vm.expectEmit(true, true, true, true);
        emit IModularValidationHook.ModuleSet(modules[1].toId(), IValidationHook(mockHook), true, true);
        ModularValidationHook hook = _deploy(modules);

        uint256[] memory ids = hook.moduleIds();
        assertEq(ids.length, 2);

        uint256 id0 = modules[0].toId();
        uint256 id1 = modules[1].toId();

        bool found0;
        bool found1;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == id0) found0 = true;
            if (ids[i] == id1) found1 = true;
        }
        assertTrue(found0);
        assertTrue(found1);

        Module memory module0 = hook.modules(id0);
        assertEq(address(module0.hook), address(mockHook));
        assertEq(module0.hasHookData, false);
        assertEq(module0.allowRevert, false);

        Module memory module1 = hook.modules(id1);
        assertEq(address(module1.hook), address(mockHook));
        assertEq(module1.hasHookData, true);
        assertEq(module1.allowRevert, true);
    }

    function test_setHookData_onlyModuleHook_reverts(bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData =
            ModuleHookData({requireSenderIsOwner: true, isReplayable: false, validUntilBlock: 1, hookData: _hookData});

        vm.expectRevert(IModularValidationHook.NotSetter.selector);
        hook.setHookData(moduleId, owner, moduleHookData);
    }

    function test_deleteHookData_onlyModuleHook_reverts(Module memory module) public givenValidModuleId(module) {
        vm.assume(address(module.hook) != address(0));
        Module[] memory modules = new Module[](1);
        modules[0] = module;
        ModularValidationHook hook = _deploy(modules);

        vm.expectRevert(IModularValidationHook.NotSetter.selector);
        hook.deleteHookData(module.toId(), owner);
    }

    function test_deleteHookData_deletesHookData() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true, isReplayable: false, validUntilBlock: 1, hookData: bytes('hookData')
        });

        vm.startPrank(address(mockHook));
        vm.expectEmit(true, true, true, true);
        emit IModularValidationHook.HookDataSet(
            moduleId, owner, moduleHookData.validUntilBlock, moduleHookData.hookData
        );
        hook.setHookData(moduleId, owner, moduleHookData);

        vm.expectEmit(true, true, true, true);
        emit IModularValidationHook.HookDataDeleted(moduleId, owner);
        hook.deleteHookData(moduleId, owner);

        vm.stopPrank();

        // assert all set to default values
        assertEq(hook.moduleHookData(moduleId, owner).hookData, bytes(''));
        assertEq(hook.moduleHookData(moduleId, owner).validUntilBlock, 0);
        assertEq(hook.moduleHookData(moduleId, owner).requireSenderIsOwner, false);
        assertEq(hook.moduleHookData(moduleId, owner).isReplayable, false);
    }

    function test_validate_whenHookDataRequired_andNoData_reverts() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        vm.expectRevert(abi.encodeWithSelector(IModularValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_singleModule_usesProvidedHookData_gas() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](1);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData'));

        hook.validate(0, 0, owner, sender, abi.encode(hookData));
        vm.snapshotGasLastCall('validate_singleModule_usesProvidedHookData');
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_multiModule_usesProvidedHookData_gas() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](1);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData0'));

        vm.expectCall(
            address(mockHook),
            abi.encodeWithSelector(mockHook.validate.selector, 0, 0, owner, sender, bytes('hookData0'))
        );
        hook.validate(0, 0, owner, sender, abi.encode(hookData));
        vm.snapshotGasLastCall('validate_multiModule_usesProvidedHookData');
    }

    function test_validate_usesProvidedHookData(uint256 _maxPrice, uint128 _amount, bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        vm.assume(_hookData.length > 0);

        uint256 moduleId = modules[0].toId();
        hook.validate(_maxPrice, _amount, owner, sender, abi.encode(_toBytesArray(abi.encode(moduleId, _hookData))));
    }

    function test_validate_usesCachedHookData(uint256 _maxPrice, uint128 _amount, bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        vm.assume(_hookData.length > 0);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: _hookData
        });

        vm.prank(address(mockHook));
        vm.expectEmit(true, true, true, true);
        emit IModularValidationHook.HookDataSet(
            moduleId, owner, moduleHookData.validUntilBlock, moduleHookData.hookData
        );
        hook.setHookData(moduleId, owner, moduleHookData);

        hook.validate(_maxPrice, _amount, owner, owner, abi.encode(new bytes[](0)));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_singleModule_usesCachedHookData_gas() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](1);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData'));
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('hookData')
        });

        vm.prank(address(mockHook));
        hook.setHookData(modules[0].toId(), owner, moduleHookData);

        hook.validate(0, 0, owner, owner, abi.encode(new bytes[](0)));
        vm.snapshotGasLastCall('validate_singleModule_usesCachedHookData');
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_multiModule_usesCachedHookData_gas() public {
        vm.label(address(mockHook), 'mockHook');
        MockValidationHook mockHook2 = new MockValidationHook();
        vm.label(address(mockHook2), 'mockHook2');
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook2)});
        ModularValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](1);
        hookData[0] = abi.encode(modules[0].toId(), bytes('provided'));

        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('cached')
        });

        vm.prank(address(mockHook));
        hook.setHookData(modules[0].toId(), owner, moduleHookData);
        vm.prank(address(mockHook2));
        hook.setHookData(modules[1].toId(), owner, moduleHookData);

        // Cached hook data is preferred over provided
        vm.expectCall(
            address(mockHook), abi.encodeWithSelector(mockHook.validate.selector, 0, 0, owner, owner, bytes('cached'))
        );
        vm.expectCall(
            address(mockHook2), abi.encodeWithSelector(mockHook2.validate.selector, 0, 0, owner, owner, bytes('cached'))
        );
        hook.validate(0, 0, owner, owner, abi.encode(hookData));
        vm.snapshotGasLastCall('validate_multiModule_usesCachedHookData');
    }

    function test_validate_whenCachedHookDataRequiresSenderIsOwner_reverts(address _notOwner) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('cached')
        });

        vm.prank(address(mockHook));
        hook.setHookData(moduleId, owner, moduleHookData);

        vm.assume(_notOwner != owner);
        vm.expectRevert(abi.encodeWithSelector(IModularValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, _notOwner, abi.encode(new bytes[](0)));
    }

    function test_validate_whenCachedHookDataExpired_reverts(uint64 _validUntilBlock, bytes memory _expected) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        vm.assume(_validUntilBlock > block.number && _validUntilBlock < type(uint64).max);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true, isReplayable: false, validUntilBlock: _validUntilBlock, hookData: _expected
        });

        vm.prank(address(mockHook));
        hook.setHookData(moduleId, owner, moduleHookData);

        vm.roll(_validUntilBlock + 1);

        vm.expectRevert(abi.encodeWithSelector(IModularValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, owner, abi.encode(new bytes[](0)));
    }

    function test_validate_allowRevert_doesNotRevert() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: true, hook: IValidationHook(revertingHook)});
        ModularValidationHook hook = _deploy(modules);

        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_multipleModules_allowRevert_doesNotRevert() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: false, allowRevert: true, hook: IValidationHook(revertingHook)});
        modules[1] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_revertingHookWithoutAllowRevert_reverts() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHook)});
        ModularValidationHook hook = _deploy(modules);

        vm.expectRevert();
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_revertsWithHookReason() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHookWithString)});
        ModularValidationHook hook = _deploy(modules);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(revertingHookWithString),
                IValidationHook.validate.selector,
                abi.encodeWithSignature('Error(string)', 'reason'),
                abi.encodeWithSelector(IModularValidationHook.ValidateReverted.selector)
            )
        );
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_revertsWithCustomError() public {
        Module[] memory modules = new Module[](1);
        modules[0] =
            Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHookWithCustomError)});
        ModularValidationHook hook = _deploy(modules);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(revertingHookWithCustomError),
                IValidationHook.validate.selector,
                abi.encodeWithSelector(MockRevertingValidationHookWithCustomError.CustomError.selector),
                abi.encodeWithSelector(IModularValidationHook.ValidateReverted.selector)
            )
        );
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_simulate_returnsRevertReason() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHookWithString)});
        ModularValidationHook hook = _deploy(modules);

        bytes memory expected = abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(revertingHookWithString),
            IValidationHook.validate.selector,
            abi.encodeWithSignature('Error(string)', 'reason'),
            abi.encodeWithSelector(IModularValidationHook.ValidateReverted.selector)
        );
        bytes memory reason = hook.simulate(0, 0, owner, sender, abi.encode(new bytes[](0)));
        assertEq(reason, expected);
    }

    function test_simulate_returnsEmptyBytesArrayWhenSuccessful() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        ModularValidationHook hook = _deploy(modules);

        bytes memory reason = hook.simulate(0, 0, owner, sender, abi.encode(new bytes[](0)));
        assertEq(reason, bytes(''));
    }
}
