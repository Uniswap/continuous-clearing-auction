// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {MockStepStorage} from 'btt/mocks/MockStepStorage.sol';

import {BttBase, Step} from 'btt/BttBase.sol';
import {IStepStorage} from 'continuous-clearing-auction/interfaces/IStepStorage.sol';
import {AuctionStep} from 'continuous-clearing-auction/libraries/StepLib.sol';

contract AdvanceStepTest is BttBase {
    MockStepStorage public auctionStepStorage;

    function test_GivenOffsetGT_LENGTH(Step[] memory _steps, uint64 _startBlock) external {
        // it reverts with {AuctionIsOver}

        (bytes memory auctionStepsData, uint256 numberOfBlocks,) = generateAuctionSteps(_steps);
        uint64 startBlock = uint64(bound(_startBlock, 1, type(uint64).max - numberOfBlocks));
        uint64 endBlock = startBlock + uint64(numberOfBlocks);

        auctionStepStorage = new MockStepStorage(auctionStepsData, startBlock, endBlock);

        // Then proceed through the list until we are bast the end block.
        for (uint256 i = 8; i < auctionStepsData.length; i += 8) {
            auctionStepStorage.advanceStep();
        }

        vm.expectRevert(IStepStorage.AuctionIsOver.selector);
        auctionStepStorage.advanceStep();
    }

    modifier givenOffsetLE_LENGTH() {
        _;
    }

    function test_WhenPrevBlockEndEQ0(Step[] memory _steps, uint64 _startBlock) external givenOffsetLE_LENGTH {
        // it sets start to START_BLOCK
        // it sets end to start + blockDelta
        // it writes $step
        // it writes $_offset
        // it emits {AuctionStepRecorded}
        // it returns $step

        (bytes memory auctionStepsData, uint256 numberOfBlocks, Step[] memory steps) = generateAuctionSteps(_steps);
        uint64 startBlock = uint64(bound(_startBlock, 2, type(uint64).max - numberOfBlocks));
        uint64 endBlock = startBlock + uint64(numberOfBlocks);

        // For the very first step, we have not previously written any data to `step` so the `endBlock` is 0
        // This is executed as part of the constructor.

        vm.expectEmit(true, true, true, true);
        emit IStepStorage.AuctionStepRecorded(startBlock, startBlock + steps[0].blockDelta, steps[0].mps);
        vm.record();
        auctionStepStorage = new MockStepStorage(auctionStepsData, startBlock, endBlock);
        (, bytes32[] memory writes) = vm.accesses(address(auctionStepStorage));

        if (!isCoverage()) {
            // 1 write to update the step
            // 1 write to update the offset
            assertEq(writes.length, 2);
        }

        AuctionStep memory step = auctionStepStorage.step();

        assertEq(step.startBlock, startBlock);
        assertEq(step.endBlock, startBlock + steps[0].blockDelta);
        assertGt(step.endBlock, step.startBlock);
        assertEq(step.mps, steps[0].mps);
        assertEq(startBlock, auctionStepStorage.startBlock());
    }

    function test_WhenStartNEQ0(Step[] memory _steps, uint64 _startBlock) external givenOffsetLE_LENGTH {
        // it sets start to endBlock of previous step
        // it sets end to start + delta
        // it writes $step
        // it reads from _pointer
        // it writes $_offset
        // it emits {AuctionStepRecorded}
        // it returns $step

        (bytes memory auctionStepsData, uint256 numberOfBlocks, Step[] memory steps) = generateAuctionSteps(_steps);
        uint64 startBlock = uint64(bound(_startBlock, 2, type(uint64).max - numberOfBlocks));
        uint64 endBlock = startBlock + uint64(numberOfBlocks);

        // For the very first step, we have not previously written any data to `step` so the `endBlock` is 0
        // This is executed as part of the constructor.

        auctionStepStorage = new MockStepStorage(auctionStepsData, startBlock, endBlock);

        AuctionStep memory prevStep = auctionStepStorage.step();

        for (uint256 i = 8; i < auctionStepsData.length; i += 8) {
            vm.expectEmit(true, true, true, true, address(auctionStepStorage));
            emit IStepStorage.AuctionStepRecorded(
                prevStep.endBlock, prevStep.endBlock + steps[i / 8].blockDelta, steps[i / 8].mps
            );
            vm.record();
            AuctionStep memory step = auctionStepStorage.advanceStep();
            (, bytes32[] memory writes) = vm.accesses(address(auctionStepStorage));

            if (!isCoverage()) {
                // 1 writes to update the step
                // 1 write to update the offset
                assertEq(writes.length, 2);

                // We ensure that the offset was updated correctly
                assertEq(uint256(vm.load(address(auctionStepStorage), writes[1])), i + 8);
            }

            assertEq(step, auctionStepStorage.step());

            assertEq(step.startBlock, prevStep.endBlock);
            assertEq(step.endBlock, step.startBlock + steps[i / 8].blockDelta);
            assertEq(step.mps, steps[i / 8].mps);
            assertGt(step.endBlock, step.startBlock);

            prevStep = step;
        }

        emit log_named_uint('endBlock', endBlock);

        vm.expectRevert(IStepStorage.AuctionIsOver.selector);
        auctionStepStorage.advanceStep();
    }
}
