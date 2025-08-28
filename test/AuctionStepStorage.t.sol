// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockAuctionStepStorage} from './utils/MockAuctionStepStorage.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionStepStorageTest is Test {
    using AuctionStepsBuilder for bytes;
    using AuctionStepLib for *;

    uint64 public auctionStartBlock;

    function setUp() public {
        auctionStartBlock = uint64(block.number);
    }

    function _create(bytes memory auctionStepsData, uint256 startBlock, uint256 endBlock)
        internal
        returns (MockAuctionStepStorage)
    {
        return new MockAuctionStepStorage(auctionStepsData, uint64(startBlock), uint64(endBlock));
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

    function test_advanceStep_initializesFirstStep() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        MockAuctionStepStorage auctionStepStorage =
            _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        (uint24 mps, uint64 startBlock, uint64 endBlock) = auctionStepStorage.step();

        assertEq(mps, 1);
        assertEq(startBlock, auctionStartBlock);
        assertEq(endBlock, auctionStartBlock + 1e7);
    }

    function test_advanceStep_usesStartBlock() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);

        // Advance many blocks in the future
        vm.roll(auctionStartBlock + 100);

        MockAuctionStepStorage auctionStepStorage =
            _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        // Expect startBlock to be auction.startBlock
        (uint24 mps, uint64 startBlock, uint64 endBlock) = auctionStepStorage.step();
        // Assert that the current block is the next block
        assertEq(block.number, auctionStartBlock + 100);
        assertEq(mps, 1);
        assertEq(startBlock, auctionStartBlock);
        assertEq(endBlock, auctionStartBlock + 1e7);
    }

    function test_advanceStep_succeeds() public {
        uint256 step1EndBlock = auctionStartBlock + 1e7 / 2;
        uint256 step2EndBlock = step1EndBlock + 1e7 / 4;
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, uint40(step1EndBlock - auctionStartBlock))
            .addStep(2, uint40(step2EndBlock - step1EndBlock));
        MockAuctionStepStorage auctionStepStorage = _create(auctionStepsData, auctionStartBlock, step2EndBlock);

        // Expect first step to be initialized
        (uint24 mps, uint64 startBlock, uint64 endBlock) = auctionStepStorage.step();
        assertEq(mps, 1);
        assertEq(startBlock, auctionStartBlock);
        assertEq(endBlock, step1EndBlock);

        vm.expectEmit(true, true, true, true);
        emit IAuctionStepStorage.AuctionStepRecorded(step1EndBlock, step2EndBlock, 2);
        auctionStepStorage.advanceStep();

        (mps, startBlock, endBlock) = auctionStepStorage.step();

        assertEq(mps, 2);
        assertEq(startBlock, step1EndBlock);
        assertEq(endBlock, step2EndBlock);
    }

    function test_emptyAuctionStepsData_reverts_withInvalidAuctionDataLength() public {
        bytes memory auctionStepsData = bytes('');
        vm.expectRevert(IAuctionStepStorage.InvalidAuctionDataLength.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_reverts_withInvalidAuctionDataLength() public {
        // Expects to be in increments of 8 bytes
        bytes memory auctionStepsData = abi.encodePacked(uint32(1));
        vm.expectRevert(IAuctionStepStorage.InvalidAuctionDataLength.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_reverts_withInvalidMps() public {
        // The sum is only 100, but must be 1e7
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 100);
        vm.expectRevert(IAuctionStepStorage.InvalidMps.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);
    }

    function test_exceedsMps_reverts_withInvalidMps() public {
        // The sum is 1e7 + 1, but must be 1e7
        uint40 blockDelta = 1e7 + 1;
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, blockDelta);
        vm.expectRevert(IAuctionStepStorage.InvalidMps.selector);
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + blockDelta);
    }

    function test_reverts_withInvalidEndBlock() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        vm.expectRevert(IAuctionStepStorage.InvalidEndBlock.selector);
        // The end block should be block.number + 1e7, but is 1e7 - 1
        _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7 - 1);
    }

    function test_advanceStep_exceedsLength_reverts_withAuctionIsOver() public {
        // Create auction with only one step
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        MockAuctionStepStorage auctionStepStorage =
            _create(auctionStepsData, auctionStartBlock, auctionStartBlock + 1e7);

        // First call to advanceStep - this should succeed (offset goes from 8 to 16)
        auctionStepStorage.advanceStep();

        // Second call to advanceStep - now offset (16) > _length (8), should revert
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auctionStepStorage.advanceStep();
    }
}
