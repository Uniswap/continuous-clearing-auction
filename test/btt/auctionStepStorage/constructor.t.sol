// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {MockStepStorage} from 'btt/mocks/MockStepStorage.sol';

import {BttBase, Step} from 'btt/BttBase.sol';
import {IStepStorage} from 'continuous-clearing-auction/interfaces/IStepStorage.sol';
import {AuctionStep, StepLib} from 'continuous-clearing-auction/libraries/StepLib.sol';

contract ConstructorTest is BttBase {
    MockStepStorage public auctionStepStorage;

    // Note that the failures in internal functions should be covered in the internal functions

    function test_WhenStartBlockGEEndBlock() external {
        // it reverts with {InvalidEndBlock}

        vm.expectRevert(IStepStorage.InvalidEndBlock.selector);
        auctionStepStorage = new MockStepStorage(new bytes(0), 1, 0);
    }

    function test_WhenStartBlockLEEndBlock(Step[] memory _steps, uint64 _startBlock) external {
        // it etches START_BLOCK
        // it etches END_BLOCK
        // it etches _LENGTH
        // it etches $_pointer
        // it writes $_offset
        // it writes $step
        // it emits {AuctionStepRecorded}

        (bytes memory auctionStepsData, uint256 numberOfBlocks, Step[] memory steps) = generateAuctionSteps(_steps);
        uint64 startBlock = uint64(bound(_startBlock, 1, type(uint64).max - numberOfBlocks));

        vm.expectEmit(true, true, true, true);
        emit IStepStorage.AuctionStepRecorded(startBlock, startBlock + uint64(steps[0].blockDelta), steps[0].mps);
        vm.record();
        auctionStepStorage = new MockStepStorage(auctionStepsData, startBlock, startBlock + uint64(numberOfBlocks));

        (, bytes32[] memory writes) = vm.accesses(address(auctionStepStorage));

        if (!isCoverage()) {
            assertEq(writes.length, 2);
            assertEq(uint256(vm.load(address(auctionStepStorage), writes[1])), StepLib.UINT64_SIZE, 'offset'); // The offset
        }

        assertEq(auctionStepStorage.startBlock(), startBlock);
        assertEq(auctionStepStorage.endBlock(), startBlock + uint64(numberOfBlocks));

        assertEq(
            auctionStepStorage.step(),
            AuctionStep({startBlock: startBlock, endBlock: startBlock + uint64(steps[0].blockDelta), mps: steps[0].mps})
        );

        bytes memory expectedCode = bytes.concat(bytes1(0x00), auctionStepsData);
        assertEq(auctionStepStorage.pointer().code, expectedCode);
    }
}
