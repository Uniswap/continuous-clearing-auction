// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {IModuleValidationHook, Module, ModuleHookData} from 'src/interfaces/periphery/IModuleValidationHook.sol';
import {ModuleValidationHook, ValidationModuleLib} from 'src/periphery/validationHooks/ModuleValidationHook.sol';
import {
    MockRevertingValidationHook,
    MockRevertingValidationHookErrorWithString
} from 'test/utils/MockRevertingValidationHook.sol';
import {MockValidationHook} from 'test/utils/MockValidationHook.sol';

contract ModuleValidationHookTest is Test {
    using ValidationModuleLib for Module;

    address setter = makeAddr('setter');
    address owner = makeAddr('owner');
    address sender = makeAddr('sender');

    MockValidationHook mockHook;
    MockRevertingValidationHook revertingHook;
    MockRevertingValidationHookErrorWithString revertingHookWithString;

    function setUp() public {
        mockHook = new MockValidationHook();
        revertingHook = new MockRevertingValidationHook();
        revertingHookWithString = new MockRevertingValidationHookErrorWithString();
    }

    function _deploy(Module[] memory _modules) internal returns (ModuleValidationHook) {
        return new ModuleValidationHook(_modules, setter);
    }

    function _toBytesArray(bytes memory _data) internal pure returns (bytes[] memory wrapped) {
        wrapped = new bytes[](1);
        wrapped[0] = _data;
    }

    function test_constructor_revertsWhenHookIsZero() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(address(0))});
        vm.expectRevert(ModuleValidationHook.InvalidModuleHook.selector);
        _deploy(modules);
    }

    function test_moduleIdsAndModules_areSet() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: true, allowRevert: true, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

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

    function test_setHookData_onlySetter_reverts(bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData =
            ModuleHookData({requireSenderIsOwner: true, isReplayable: false, validUntilBlock: 1, hookData: _hookData});

        vm.expectRevert(ModuleValidationHook.NotSetter.selector);
        hook.setHookData(moduleId, owner, moduleHookData);
    }

    function test_validate_whenHookDataRequired_andNoData_reverts() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        vm.expectRevert(abi.encodeWithSelector(ModuleValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_singleModule_usesProvidedHookData_gas() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

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
        modules[1] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](2);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData0'));
        hookData[1] = abi.encode(modules[1].toId(), bytes('hookData1'));

        hook.validate(0, 0, owner, sender, abi.encode(hookData));
        vm.snapshotGasLastCall('validate_multiModule_usesProvidedHookData');
    }

    function test_validate_usesProvidedHookData(uint256 _maxPrice, uint128 _amount, bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        vm.assume(_hookData.length > 0);

        uint256 moduleId = modules[0].toId();
        hook.validate(_maxPrice, _amount, owner, sender, abi.encode(_toBytesArray(abi.encode(moduleId, _hookData))));
    }

    function test_validate_usesCachedHookData(uint256 _maxPrice, uint128 _amount, bytes memory _hookData) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        vm.assume(_hookData.length > 0);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: _hookData
        });

        vm.prank(setter);
        hook.setHookData(moduleId, owner, moduleHookData);

        hook.validate(_maxPrice, _amount, owner, owner, abi.encode(new bytes[](0)));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_singleModule_usesCachedHookData_gas() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](1);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData'));
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('hookData')
        });

        vm.prank(setter);
        hook.setHookData(modules[0].toId(), owner, moduleHookData);

        hook.validate(0, 0, owner, owner, abi.encode(new bytes[](0)));
        vm.snapshotGasLastCall('validate_singleModule_usesCachedHookData');
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_validate_multiModule_usesCachedHookData_gas() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        modules[1] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        bytes[] memory hookData = new bytes[](2);
        hookData[0] = abi.encode(modules[0].toId(), bytes('hookData0'));
        hookData[1] = abi.encode(modules[1].toId(), bytes('hookData1'));

        hook.validate(0, 0, owner, owner, abi.encode(hookData));
        vm.snapshotGasLastCall('validate_multiModule_usesCachedHookData');
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('hookData')
        });

        vm.prank(setter);
        hook.setHookData(modules[0].toId(), owner, moduleHookData);
        vm.prank(setter);
        hook.setHookData(modules[1].toId(), owner, moduleHookData);

        hook.validate(0, 0, owner, owner, abi.encode(new bytes[](0)));
        vm.snapshotGasLastCall('validate_multiModule_usesCachedHookData');
    }

    function test_validate_whenCachedHookDataRequiresSenderIsOwner_reverts(address _notOwner) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        uint256 moduleId = modules[0].toId();
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true,
            isReplayable: false,
            validUntilBlock: uint64(block.number + 1),
            hookData: bytes('cached')
        });

        vm.prank(setter);
        hook.setHookData(moduleId, owner, moduleHookData);

        vm.assume(_notOwner != owner);
        vm.expectRevert(abi.encodeWithSelector(ModuleValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, _notOwner, abi.encode(new bytes[](0)));
    }

    function test_validate_whenCachedHookDataExpired_reverts(uint64 _currentBlock, bytes memory _expected) public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: true, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        vm.assume(_currentBlock > 0);
        vm.roll(_currentBlock);
        uint256 moduleId = modules[0].toId();
        uint64 validUntilBlock = uint64(_bound(_currentBlock - 1, 0, _currentBlock - 1));
        ModuleHookData memory moduleHookData = ModuleHookData({
            requireSenderIsOwner: true, isReplayable: false, validUntilBlock: validUntilBlock, hookData: _expected
        });

        vm.prank(setter);
        hook.setHookData(moduleId, owner, moduleHookData);

        vm.expectRevert(abi.encodeWithSelector(ModuleValidationHook.HookDataRequired.selector, mockHook));
        hook.validate(0, 0, owner, owner, abi.encode(new bytes[](0)));
    }

    function test_validate_allowRevert_doesNotRevert() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: true, hook: IValidationHook(revertingHook)});
        ModuleValidationHook hook = _deploy(modules);

        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_multipleModules_allowRevert_doesNotRevert() public {
        Module[] memory modules = new Module[](2);
        modules[0] = Module({hasHookData: false, allowRevert: true, hook: IValidationHook(revertingHook)});
        modules[1] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(mockHook)});
        ModuleValidationHook hook = _deploy(modules);

        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_revertingHookWithoutAllowRevert_reverts() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHook)});
        ModuleValidationHook hook = _deploy(modules);

        vm.expectRevert();
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_validate_revertsWithHookReason() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHookWithString)});
        ModuleValidationHook hook = _deploy(modules);

        vm.expectRevert(bytes('reason'));
        hook.validate(0, 0, owner, sender, abi.encode(new bytes[](0)));
    }

    function test_simulate_returnsRevertReason() public {
        Module[] memory modules = new Module[](1);
        modules[0] = Module({hasHookData: false, allowRevert: false, hook: IValidationHook(revertingHookWithString)});
        ModuleValidationHook hook = _deploy(modules);

        bytes memory reason = hook.simulate(0, 0, owner, sender, abi.encode(new bytes[](0)));
        bytes memory expected = abi.encodeWithSignature('Error(string)', 'reason');
        assertEq(reason, expected);
    }
}
