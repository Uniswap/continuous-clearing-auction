// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase, Step} from 'btt/BttBase.sol';
import {CompactStep, CompactStepLib} from 'btt/libraries/auctionStepLib/StepUtils.sol';
import {MockAuctionStepStorage} from 'btt/mocks/MockAuctionStepStorage.sol';
import {SSTORE2} from 'solady/utils/SSTORE2.sol';
import {IAuctionStepStorage} from 'twap-auction/interfaces/IAuctionStepStorage.sol';
import {AuctionStep} from 'twap-auction/libraries/AuctionStepLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';

contract ValidateTest is BttBase {
    using SSTORE2 for *;

    MockAuctionStepStorage public auctionStepStorage;

    function test_WhenAuctionStepsDataLengthEQ0() external {
        // it reverts with {InvalidAuctionDataLength}

        vm.expectRevert(IAuctionStepStorage.InvalidAuctionDataLength.selector);
        auctionStepStorage = new MockAuctionStepStorage(bytes(''), 1, 2);
    }

    modifier whenAuctionStepsDataLengthNEQ0() {
        _;
    }

    function test_WhenAuctionStepsDataLengthIsNotAMultipleOfUINT64_SIZE() external whenAuctionStepsDataLengthNEQ0 {
        // it reverts with {InvalidAuctionDataLength}

        vm.expectRevert(IAuctionStepStorage.InvalidAuctionDataLength.selector);
        auctionStepStorage = new MockAuctionStepStorage(new bytes(7), 1, 2);
    }

    modifier whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE() {
        _;
    }

    function test_WhenAuctionStepsDataLengthNEQ_LENGTH()
        external
        whenAuctionStepsDataLengthNEQ0
        whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE
    {
        // it reverts with {InvalidAuctionDataLength}

        Step[] memory steps = new Step[](1);
        steps[0].mps = 1e7;
        steps[0].blockDelta = 1;
        (bytes memory auctionStepsData, uint256 numberOfBlocks,) = generateAuctionSteps(steps);

        auctionStepStorage = new MockAuctionStepStorage(auctionStepsData, 1, 1 + uint64(numberOfBlocks));

        address pointer = new bytes(16).write();

        vm.expectRevert(IAuctionStepStorage.InvalidAuctionDataLength.selector);
        auctionStepStorage.validate(pointer);
    }

    modifier whenAuctionStepsDataLengthEQ_LENGTH() {
        _;
    }

    function test_WhenAuctionStepWithDeltaEQ0()
        external
        whenAuctionStepsDataLengthNEQ0
        whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE
        whenAuctionStepsDataLengthEQ_LENGTH
    {
        // it reverts with {StepBlockDeltaCannotBeZero}

        CompactStep[] memory steps = new CompactStep[](1);
        bytes memory auctionStepsData = CompactStepLib.pack(steps);

        vm.expectRevert(IAuctionStepStorage.StepBlockDeltaCannotBeZero.selector);
        auctionStepStorage = new MockAuctionStepStorage(auctionStepsData, 1, 2);
    }

    modifier whenNoAuctionStepWithDeltaEQ0() {
        _;
    }

    function test_WhenSumOfMpsTimesDeltaNEQMPS()
        external
        whenAuctionStepsDataLengthNEQ0
        whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE
        whenAuctionStepsDataLengthEQ_LENGTH
        whenNoAuctionStepWithDeltaEQ0
    {
        // it reverts with {InvalidStepDataMps}

        CompactStep[] memory steps = new CompactStep[](1);
        steps[0] = CompactStepLib.create(1e7 - 1, 1);
        bytes memory auctionStepsData = CompactStepLib.pack(steps);

        vm.expectRevert(
            abi.encodeWithSelector(IAuctionStepStorage.InvalidStepDataMps.selector, 1e7 - 1, ConstantsLib.MPS)
        );
        auctionStepStorage = new MockAuctionStepStorage(auctionStepsData, 1, 2);
    }

    modifier whenSumOfMpsTimesDeltaEQMPS() {
        _;
    }

    function test_WhenSumOfBlockDeltaAndStartBlockNEQEndBlock()
        external
        whenAuctionStepsDataLengthNEQ0
        whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE
        whenAuctionStepsDataLengthEQ_LENGTH
        whenNoAuctionStepWithDeltaEQ0
        whenSumOfMpsTimesDeltaEQMPS
    {
        // it reverts with {InvalidEndBlockGivenStepData}
        CompactStep[] memory steps = new CompactStep[](1);
        steps[0] = CompactStepLib.create(1e7, 1);
        bytes memory auctionStepsData = CompactStepLib.pack(steps);

        vm.expectRevert(abi.encodeWithSelector(IAuctionStepStorage.InvalidEndBlockGivenStepData.selector, 2, 3));
        auctionStepStorage = new MockAuctionStepStorage(auctionStepsData, 1, 3);
    }

    function test_WhenSumOfBlockDeltaAndStartBlockEQEndBlock(Step[] memory _steps, uint64 _startBlock)
        external
        whenAuctionStepsDataLengthNEQ0
        whenAuctionStepsDataLengthIsMultipleOfUINT64_SIZE
        whenAuctionStepsDataLengthEQ_LENGTH
        whenNoAuctionStepWithDeltaEQ0
        whenSumOfMpsTimesDeltaEQMPS
    {
        // it does nothing

        (bytes memory auctionStepsData, uint256 numberOfBlocks,) = generateAuctionSteps(_steps);
        uint64 startBlock = uint64(bound(_startBlock, 1, type(uint64).max - numberOfBlocks));
        auctionStepStorage =
            new MockAuctionStepStorage(auctionStepsData, startBlock, startBlock + uint64(numberOfBlocks));

        address pointer = auctionStepStorage.pointer();
        vm.record();
        auctionStepStorage.validate(pointer);
        (, bytes32[] memory writes) = vm.accesses(address(auctionStepStorage));
        assertEq(writes.length, 0);
    }
}
