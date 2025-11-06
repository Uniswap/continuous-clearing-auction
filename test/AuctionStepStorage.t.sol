// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IStepStorage} from '../src/interfaces/IStepStorage.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {StepLib} from '../src/libraries/StepLib.sol';
import {AuctionStep} from '../src/libraries/StepLib.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockStepStorage} from './utils/MockStepStorage.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionStepStorageTest is Test {
    using AuctionStepsBuilder for bytes;
    using StepLib for *;

    uint64 public auctionStartBlock;

    function setUp() public {
        auctionStartBlock = uint64(block.number);
    }

    function _create(bytes memory auctionStepsData, uint256 startBlock, uint256 endBlock)
        internal
        returns (MockStepStorage)
    {
        return new MockStepStorage(auctionStepsData, uint64(startBlock), uint64(endBlock));
    }

    function test_canBeConstructed_fuzz(uint8 numIterations) public {
        for (uint8 i = 0; i < numIterations; i++) {
            bytes memory auctionStepsData = AuctionStepsBuilder.init();
            uint24 mpsLeft = 1e7;
            uint64 cumulativeBlockDelta = 0;
            while (mpsLeft > 0) {
                // random values between 0 and 1e4
                uint24 mps = uint24(vm.randomUint() % 1e4);
                uint40 blockDelta = uint40(_bound(uint40(vm.randomUint() % 1e4), 1, 1e4));
                if (mpsLeft < mps * blockDelta) {
                    break;
                }
                mpsLeft -= uint24(mps * blockDelta);
                cumulativeBlockDelta += blockDelta;
                auctionStepsData = auctionStepsData.addStep(mps, blockDelta);
            }
            // Add the remaining mps as a single step
            if (mpsLeft > 0) {
                auctionStepsData = auctionStepsData.addStep(mpsLeft, 1);
                cumulativeBlockDelta += 1;
            }
            _create(auctionStepsData, auctionStartBlock, auctionStartBlock + cumulativeBlockDelta);
        }
    }

    function test_canBeConstructed() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_canBeConstructed_withIncreasingMps() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 5e6).addStep(2, 25e5);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 5e6 + 25e5);
    }

    function test_canBeConstructed_withLeadingZeroMpsStep() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(0, 1e7).addStep(1, 1e7);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 2e7);
    }

    function test_canBeConstructed_withMiddleZeroMpsStep() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 5e6).addStep(0, 1e7).addStep(2, 25e5);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 5e6 + 1e7 + 25e5);
    }

    function test_constructor_revertsWithInvalidEndBlock() public {
        // Not checked in this test
        bytes memory auctionStepsData = bytes('');
        vm.expectRevert(IStepStorage.InvalidEndBlock.selector);
        // Endblock is before startblock
        _create(auctionStepsData, 1, 0);

        vm.expectRevert(IStepStorage.InvalidEndBlock.selector);
        // StartBlock == EndBlock
        _create(auctionStepsData, 1, 1);
    }

    function test_validate_revertsWithStepBlockDeltaCannotBeZero() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7).addStep(1, 0);
        vm.expectRevert(IStepStorage.StepBlockDeltaCannotBeZero.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_advanceStep_initializesFirstStep() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        MockStepStorage auctionStepStorage = _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        AuctionStep memory step = auctionStepStorage.step();

        assertEq(step.mps, 1);
        assertEq(step.startBlock, auctionStartBlock);
        assertEq(step.endBlock, auctionStartBlock + 1e7);
    }

    function test_advanceStep_usesStartBlock() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);

        // Advance many blocks in the future
        vm.roll(auctionStartBlock + 100);

        MockStepStorage auctionStepStorage = _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        // Expect startBlock to be auction.startBlock
        AuctionStep memory step = auctionStepStorage.step();
        // Assert that the current block is the next block
        assertEq(block.number, auctionStartBlock + 100);
        assertEq(step.mps, 1);
        assertEq(step.startBlock, auctionStartBlock);
        assertEq(step.endBlock, auctionStartBlock + 1e7);
    }

    function test_advanceStep_succeeds() public {
        uint256 step1EndBlock = auctionStartBlock + 1e7 / 2;
        uint256 step2EndBlock = step1EndBlock + 1e7 / 4;
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, uint40(step1EndBlock - auctionStartBlock))
            .addStep(2, uint40(step2EndBlock - step1EndBlock));
        MockStepStorage auctionStepStorage = _create(auctionStepsData, auctionStartBlock, step2EndBlock);

        // Expect first step to be initialized
        AuctionStep memory step = auctionStepStorage.step();
        assertEq(step.mps, 1);
        assertEq(step.startBlock, auctionStartBlock);
        assertEq(step.endBlock, step1EndBlock);

        vm.expectEmit(true, true, true, true);
        emit IStepStorage.AuctionStepRecorded(step1EndBlock, step2EndBlock, 2);
        auctionStepStorage.advanceStep();

        step = auctionStepStorage.step();

        assertEq(step.mps, 2);
        assertEq(step.startBlock, step1EndBlock);
        assertEq(step.endBlock, step2EndBlock);
    }

    function test_emptyAuctionStepsData_reverts_withInvalidAuctionDataLength() public {
        bytes memory auctionStepsData = bytes('');
        vm.expectRevert(IStepStorage.InvalidAuctionDataLength.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_reverts_withInvalidAuctionDataLength() public {
        // Expects to be in increments of 8 bytes
        bytes memory auctionStepsData = abi.encodePacked(uint32(1));
        vm.expectRevert(IStepStorage.InvalidAuctionDataLength.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_reverts_withInvalidStepDataMps() public {
        // The sum is only 100, but must be 1e7
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 100);
        vm.expectRevert(abi.encodeWithSelector(IStepStorage.InvalidStepDataMps.selector, 100, ConstantsLib.MPS));
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_exceedsMps_reverts_withInvalidStepDataMps() public {
        // The sum is 1e7 + 1, but must be 1e7
        uint40 blockDelta = 1e7 + 1;
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, blockDelta);
        vm.expectRevert(abi.encodeWithSelector(IStepStorage.InvalidStepDataMps.selector, 1e7 + 1, ConstantsLib.MPS));
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + blockDelta);
    }

    function test_reverts_withInvalidEndBlockGivenStepData() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStepStorage.InvalidEndBlockGivenStepData.selector, auctionStartBlock + 1e7, auctionStartBlock + 1e7 - 1
            )
        );
        // The end block should be block.number + 1e7, but is 1e7 - 1
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7 - 1);
    }

    function test_advanceStep_exceedsLength_reverts_withAuctionIsOver() public {
        // Create auction with only one step (will perform first advanceStep)
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        MockStepStorage auctionStepStorage = _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        // Second call to advanceStep - offset already at length, should revert
        vm.expectRevert(IStepStorage.AuctionIsOver.selector);
        auctionStepStorage.advanceStep();
    }
}
