// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionState, AuctionStateLens} from '../../src/lens/AuctionStateLens.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionUnitTest} from '../unit/AuctionUnitTest.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionStateLensTest is AuctionUnitTest {
    AuctionStateLens public lens;

    function setUp() public {
        setUpMockAuction();
        lens = new AuctionStateLens();
    }

    function test_state_succeeds() public {
        uint256 snapshotId = vm.snapshot();
        Checkpoint memory checkpoint = mockAuction.checkpoint();
        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();
        uint256 expectedTotalCleared = mockAuction.totalCleared();
        bool expectedIsGraduated = mockAuction.isGraduated();

        // Revert to before the checkpoint was created
        vm.revertTo(snapshotId);
        // Check that there is no checkpoint on the auction
        assertEq(mockAuction.lastCheckpointedBlock(), 0);
        (bool success, bytes memory reason) =
            address(lens).call(abi.encodeCall(lens.state, (IContinuousClearingAuction(address(mockAuction)))));

        assertEq(success, true);
        AuctionState memory state = abi.decode(reason, (AuctionState));
        assertEq(state.checkpoint, checkpoint);
        assertEq(state.currencyRaised, expectedCurrencyRaised);
        assertEq(state.totalCleared, expectedTotalCleared);
        assertEq(state.isGraduated, expectedIsGraduated);
    }

    function test_state_mirrors_checkpoint() public {
        uint256 demand = 1e18 << FixedPoint96.RESOLUTION;
        uint256 price = params.floorPrice + params.tickSpacing;
        mockAuction.uncheckedSetSumDemandAboveClearing(demand);
        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, price);
        mockAuction.uncheckedUpdateTickDemand(price, demand);
        mockAuction.uncheckedSetNextActiveTickPrice(price);

        vm.roll(block.number + 1);

        uint256 snapshotId = vm.snapshot();
        Checkpoint memory checkpoint = mockAuction.checkpoint();
        uint256 expectedCurrencyRaised = mockAuction.currencyRaised();
        uint256 expectedTotalCleared = mockAuction.totalCleared();
        bool expectedIsGraduated = mockAuction.isGraduated();

        // Revert to before the checkpoint was created
        vm.revertTo(snapshotId);
        // Check that there is no checkpoint on the auction
        assertEq(mockAuction.lastCheckpointedBlock(), 0);
        (bool success, bytes memory reason) =
            address(lens).call(abi.encodeCall(lens.state, (IContinuousClearingAuction(address(mockAuction)))));
        assertEq(success, true);
        AuctionState memory state = abi.decode(reason, (AuctionState));
        assertEq(state.checkpoint, checkpoint);
        assertEq(state.currencyRaised, expectedCurrencyRaised);
        assertEq(state.totalCleared, expectedTotalCleared);
        assertEq(state.isGraduated, expectedIsGraduated);
    }
}
