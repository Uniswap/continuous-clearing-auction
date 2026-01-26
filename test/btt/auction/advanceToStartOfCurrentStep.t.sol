// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {AuctionStep} from 'src/libraries/StepLib.sol';

contract AdvanceToStartOfCurrentStepTest is BttBase {
    function test_WhenStepStartBlockGTLastCheckpointedBlock(AuctionFuzzConstructorParams memory _params) external {
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.lastCheckpointedBlock(), 0);

        // first step startBlock must be at startBlock
        vm.roll(auction.startBlock());
        // Assume there is more than one step in the auction
        vm.assume(auction.step().endBlock != auction.endBlock());
        // Roll until after the step ends
        vm.roll(auction.step().endBlock + 1);

        uint24 mps = auction.step().mps;
        // Without the max check the blockDelta would be step.endBlock - lastCheckpointedBlock
        // which would be greater than step.endBlock - step.startBlock
        uint64 blockDelta = auction.step().endBlock - auction.step().startBlock;
        uint64 expectedDeltaMps = mps * blockDelta;

        (, uint24 deltaMps) = auction.advanceToStartOfCurrentStep(uint64(block.number));

        assertEq(deltaMps, expectedDeltaMps);
    }

    function test_WhenStepStartBlockLTLastCheckpointedBlock(AuctionFuzzConstructorParams memory _params) external {
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        deal(mParams.token, address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        // first step startBlock must be at startBlock
        vm.roll(auction.startBlock());
        // Assume there is more than one step in the auction
        vm.assume(auction.step().endBlock != auction.endBlock());
        // Assume that the endBlock is more than one block away from the startBlock
        vm.assume(auction.step().endBlock - auction.step().startBlock > 1);
        // Roll one block into the step
        vm.roll(auction.step().startBlock + 1);

        // Now step.startBlock < lastCheckpointedBlock
        // Checkpoint, and don't expect the step to be advanced
        AuctionStep memory oldStep = auction.step();
        auction.checkpoint();
        assertEq(auction.step(), oldStep);

        // Now roll past the end of the first step
        vm.roll(auction.step().endBlock + 1);

        // Assert that the _advanceToStartOfCurrentStep function uses the lastCheckpointedBlock instead of the step.startBlock
        uint64 blockDelta = auction.step().endBlock - auction.lastCheckpointedBlock();
        uint24 expectedDeltaMps = uint24(auction.step().mps * blockDelta);
        (, uint24 deltaMps) = auction.advanceToStartOfCurrentStep(uint64(block.number));
        assertEq(deltaMps, expectedDeltaMps);
    }
}
