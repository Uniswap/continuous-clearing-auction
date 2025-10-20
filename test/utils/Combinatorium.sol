// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from 'forge-std/Vm.sol';

import {console} from 'forge-std/console.sol';

/**
 * @title Combinatorium
 * @notice Pure library for three-phase combinatorial testing
 * @dev Use with: using Combinatorium for Combinatorium.Context;
 */
library Combinatorium {
    // Enable method call syntax for library functions
    using Combinatorium for Context;

    // ============ Structures ============

    struct Space {
        string name;
        uint256 weight;
        uint256 minValue;
        uint256 maxValue;
    }

    struct TestContext {
        uint256[] selections;
        uint256 snapshotId;
    }

    struct SetupAction {
        uint256 stepNumber;
        uint256[] selections;
        bool success;
    }

    struct Mutation {
        string description;
        MutationType mutationType;
        bytes mutationData;
    }

    enum MutationType {
        SKIP_CALL,
        WRONG_PARAMETER,
        WRONG_ORDER,
        UNAUTHORIZED_CALLER,
        INVALID_STATE
    }

    /// @notice Handlers struct to group function pointers and reduce parameter count
    struct Handlers {
        function(uint256, uint256[] memory) external returns (bool) setupHandler;
        function(uint256[] memory) external returns (bool) testHandler;
        function(uint256[] memory) external returns (bool) normalHandler;
        function(uint256[] memory, Mutation memory) external returns (bool) mutationHandler;
        function(uint256, uint256[] memory) external view returns (Mutation memory) mutationSelector;
    }

    /// @notice Mutation test parameters struct to reduce stack depth
    struct MutationTestParams {
        function(uint256[] memory) external returns (bool) normalHandler;
        function(uint256[] memory, Mutation memory) external returns (bool) mutationHandler;
        function(uint256, uint256[] memory) external view returns (Mutation memory) mutationSelector;
    }

    /// @notice Main context - store this in your test contract
    struct Context {
        Space[] spaces;
        uint256 totalWeight;
        uint256 snapshotId;
        uint256 maxSetupSteps;
        SetupAction[] setupHistory;
    }

    // ============ Initialization ============

    function init(Context storage self, uint256 maxSteps) internal {
        self.maxSetupSteps = maxSteps;
    }

    // ============ Space Definition ============

    function defineSpace(Context storage self, string memory name, uint256 weight, uint256 minValue, uint256 maxValue)
        internal
    {
        self.spaces.push(Space({name: name, weight: weight, minValue: minValue, maxValue: maxValue}));
        self.totalWeight += weight;
    }

    // ============ Space Selection ============

    function selectSpaces(Context memory self, uint256 seed) internal pure returns (uint256[] memory selections) {
        require(self.spaces.length > 0, 'No spaces defined');

        selections = new uint256[](self.spaces.length);

        for (uint256 i = 0; i < self.spaces.length; i++) {
            uint256 spaceSeed = uint256(keccak256(abi.encodePacked(seed, i)));
            selections[i] = _selectFromSpace(self.spaces[i], spaceSeed);
        }

        return selections;
    }

    function _selectFromSpace(Space memory space, uint256 seed) private pure returns (uint256) {
        if (space.maxValue <= space.minValue) {
            return space.minValue;
        }

        uint256 range = space.maxValue - space.minValue;
        return space.minValue + (seed % (range + 1));
    }

    // ============ Phase 1: Setup & Snapshot ============

    function executeSetup(
        Context storage self,
        uint256 seed,
        Vm vm,
        function(uint256, uint256[] memory) external returns (bool) setupHandler
    ) internal returns (uint256 snapshotId) {
        uint256 maxSteps = self.maxSetupSteps == 0 ? 1000 : self.maxSetupSteps;
        uint256 numSteps = (seed % maxSteps) + 1;
        // uint256 numSteps = maxSteps;

        delete self.setupHistory;

        Context memory ctx = _loadContext(self);

        for (uint256 step = 0; step < numSteps; step++) {
            uint256 stepSeed = uint256(keccak256(abi.encodePacked(seed, step)));
            console.log('COMBINATORIUM: executeSetup 1');
            uint256[] memory selections = selectSpaces(ctx, stepSeed);

            console.log('COMBINATORIUM: executeSetup 2');
            bool success = setupHandler(step, selections);

            self.setupHistory.push(SetupAction({stepNumber: step, selections: selections, success: success}));
        }

        snapshotId = vm.snapshotState();
        self.snapshotId = snapshotId;

        return snapshotId;
    }

    // ============ Phase 2: Action Testing ============

    function runActionTests(
        Context storage self,
        uint256 seed,
        uint256 numActions,
        Vm vm,
        function(uint256[] memory) external returns (bool) handler
    ) internal {
        Context memory ctx = _loadContext(self);

        for (uint256 i = 0; i < numActions; i++) {
            uint256 actionSeed = uint256(keccak256(abi.encodePacked(seed, 'action', i)));

            vm.revertToState(self.snapshotId);
            self.snapshotId = vm.snapshotState();

            uint256[] memory selections = selectSpaces(ctx, actionSeed);
            require(handler(selections), 'Action should succeed');
        }
    }

    // ============ Phase 2: Mutation Testing ============

    function _executeSingleMutationTest(
        Context storage self,
        uint256 mutationSeed,
        Context memory ctx,
        Vm vm,
        MutationTestParams memory params
    ) private {
        vm.revertToState(self.snapshotId);
        self.snapshotId = vm.snapshotState();

        uint256[] memory selections = selectSpaces(ctx, mutationSeed);
        Mutation memory mutation = params.mutationSelector(mutationSeed, selections);

        // Test with mutation - should fail
        bool mutatedSuccess = params.mutationHandler(selections, mutation);
        require(!mutatedSuccess, 'Mutation should have failed');

        // Revert and test without mutation - should succeed
        vm.revertToState(self.snapshotId);
        self.snapshotId = vm.snapshotState();

        bool normalSuccess = params.normalHandler(selections);
        require(normalSuccess, 'Normal execution should succeed');

        // Restore for next test
        vm.revertToState(self.snapshotId);
        self.snapshotId = vm.snapshotState();
    }

    function runMutationTests(
        Context storage self,
        uint256 seed,
        uint256 numMutations,
        Vm vm,
        function(uint256[] memory) external returns (bool) normalHandler,
        function(uint256[] memory, Mutation memory) external returns (bool) mutationHandler,
        function(uint256, uint256[] memory) external view returns (Mutation memory) mutationSelector
    ) internal {
        Context memory ctx = _loadContext(self);

        MutationTestParams memory params = MutationTestParams({
            normalHandler: normalHandler,
            mutationHandler: mutationHandler,
            mutationSelector: mutationSelector
        });

        for (uint256 i = 0; i < numMutations; i++) {
            uint256 mutationSeed = uint256(keccak256(abi.encodePacked(seed, 'mutation', i)));
            _executeSingleMutationTest(self, mutationSeed, ctx, vm, params);
        }
    }

    // ============ Combined Workflow (Using Handlers struct) ============

    function runCombinatorial(
        Context storage self,
        uint256 seed,
        uint256 numActions,
        uint256 numMutations,
        Vm vm,
        Handlers memory handlers
    ) internal {
        // Phase 1: Setup
        self.executeSetup(seed, vm, handlers.setupHandler);

        // Phase 2a: Action tests
        self.runActionTests(seed, numActions, vm, handlers.testHandler);

        // Phase 2b: Mutation tests
        self.runMutationTests(
            seed, numMutations, vm, handlers.normalHandler, handlers.mutationHandler, handlers.mutationSelector
        );
    }

    // ============ Helpers ============

    function _loadContext(Context storage self) private view returns (Context memory ctx) {
        ctx.spaces = self.spaces;
        ctx.totalWeight = self.totalWeight;
        ctx.snapshotId = self.snapshotId;
        ctx.maxSetupSteps = self.maxSetupSteps;
        // Note: setupHistory not loaded into memory for performance
    }

    function getSetupStepCount(Context storage self) internal view returns (uint256) {
        return self.setupHistory.length;
    }
}
