// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {AuctionParameters} from '../../src/interfaces/IAuction.sol';
import {Bid} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';

import {AuctionStepsBuilder} from '../utils/AuctionStepsBuilder.sol';
import {Combinatorium} from '../utils/Combinatorium.sol';
import {FuzzBid, FuzzDeploymentParams} from '../utils/FuzzStructs.sol';

import {ExitPath, PostBidScenario, PreBidScenario} from './CombinatorialEnums.sol';
import {CombinatorialHelpers} from './CombinatorialHelpers.sol';

import {Test} from 'forge-std/Test.sol';

import {console} from 'forge-std/console.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

/**
 * @title AuctionSubmitBidCombinatorialTest
 * @notice Auction submit bid tests using Combinatorium library
 */
contract AuctionSubmitBidCombinatorialTest is CombinatorialHelpers {
    using Combinatorium for Combinatorium.Context;

    Combinatorium.Context internal ctx;

    // Space indices
    enum SpaceIndices {
        method,
        auctionSeed, // seed for the auction
        bidSeed, // seed for the bid
        preBidScenario, // scenario for pre-bid setup
        postBidScenario, // scenario for post-bid setup
        mutationRandomness // randomness for the mutation

    }

    // Method enum
    enum Method {
        submitBid,
        __length
    }

    // uint256 public constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    // uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    // uint128 public constant TOTAL_SUPPLY = 1000e18;

    uint256 public usersBidId;
    uint64 public usersBidStartBlock; // Track the block where bid was submitted
    PostBidScenario public actualPostBidScenario; // Track the actual post-bid scenario

    function setUp() public {
        // Number of steps to run in handleSetup
        ctx.init(1);

        // Action to take
        ctx.defineSpace('method', 1, 0, uint256(Method.__length) - 1);
        // Auction parameters
        ctx.defineSpace('auctionSeed', 1, 0, type(uint256).max - 1);
        // Bid parameters
        ctx.defineSpace('bidSeed', 1, 0, type(uint256).max - 1);
        // // Scenarios
        ctx.defineSpace('preBidScenario', 1, 0, uint256(PreBidScenario.__length) - 1);
        ctx.defineSpace('postBidScenario', 1, 0, uint256(PostBidScenario.__length) - 1);
        // // Mutation randomness
        ctx.defineSpace('mutationRandomness', 1, 0, type(uint256).max - 1);
    }

    // ============ Handlers ============

    function handleSetup(uint256 step, uint256[] memory selections) external returns (bool) {
        if (step == 0) {
            uint256 auctionSeed = selections[uint256(SpaceIndices.auctionSeed)];
            FuzzDeploymentParams memory auctionDeploymentParams = helper__seedBasedAuction(auctionSeed);
            setUpAuction(auctionDeploymentParams);

            // Move to the auction start block
            vm.roll(auction.startBlock());

            return true;
        }

        // Handle advanced setups for steps > 0

        // NO ADVANCED SETUP FOR STEPS > 0 RIGHT NOW AVAILABLE.
        /// TODO: Implement more steps that could setup different auction supply curves
        return false;
    }

    function handleTestAction(uint256[] memory selections) external returns (bool) {
        try this.performAction(selections) {
            verifyState(selections[uint256(SpaceIndices.method)], selections);
            return true;
        } catch {
            return false;
        }
    }

    function handleNormalAction(uint256[] memory /* selections */ ) external pure returns (bool) {
        // counter.unlock();
        // counter.setNumber(42);
        return true;
    }

    function handleMutatedAction(uint256[] memory selections, Combinatorium.Mutation memory mutation)
        external
        returns (bool)
    {
        Method method = Method(selections[uint256(SpaceIndices.method)]);

        if (method == Method.submitBid) {
            if (mutation.mutationType == Combinatorium.MutationType.WRONG_PARAMETER) {
                uint256 mutationRandomness = uint256(selections[uint256(SpaceIndices.mutationRandomness)]) % 2;

                uint256 bidSeed = selections[uint256(SpaceIndices.bidSeed)];
                (uint128 bidAmount, uint256 maxPriceQ96, uint256 bidBlock) = helper__seedBasedBid(bidSeed);

                // Extract scenario selections for scenario-aware verification
                PreBidScenario preBidScenario = PreBidScenario(selections[uint256(SpaceIndices.preBidScenario)]);
                PostBidScenario postBidScenario = PostBidScenario(selections[uint256(SpaceIndices.postBidScenario)]);
                console.log(
                    'Verifying with scenarios - Pre:', uint256(preBidScenario), 'Post:', uint256(postBidScenario)
                );

                // setup pre-bid scenario
                // helper__preBidScenario(preBidScenario, maxPrice);

                // Set the auction bidding block
                vm.roll(bidBlock);

                // Deal the caller the bid amount in ETH
                vm.deal(alice, bidAmount);
                vm.prank(alice);

                // Submit the bid
                if (mutationRandomness == 0) {
                    // value sent not matching the amount
                    try auction.submitBid{value: bidAmount - 1}(maxPriceQ96, bidAmount, alice, bytes('')) {
                        return true;
                    } catch {
                        return false;
                    }
                } else if (mutationRandomness == 1) {
                    // maxPrice not matching the tickSpacking
                    try auction.submitBid{value: bidAmount}(maxPriceQ96 + 1, bidAmount, alice, bytes('')) {
                        return true;
                    } catch {
                        return false;
                    }
                }
            }
        }

        return true; // THIS WILL FAIL ALL OTHER MUTATIONS
    }

    function selectMutation(uint256 seed, uint256[] memory /* selections */ )
        external
        pure
        returns (Combinatorium.Mutation memory)
    {
        Combinatorium.MutationType mutType = Combinatorium.MutationType.WRONG_PARAMETER;
        // counter.locked() ? Combinatorium.MutationType.WRONG_PARAMETER : Combinatorium.MutationType(seed % 3);

        return Combinatorium.Mutation({
            description: 'Test mutation',
            mutationType: mutType,
            mutationData: abi.encode(seed)
        });
    }

    function performAction(uint256[] memory selections) external {
        Method method = Method(selections[uint256(SpaceIndices.method)]);

        if (method == Method.submitBid) {
            uint256 bidSeed = selections[uint256(SpaceIndices.bidSeed)];
            (uint128 bidAmount, uint256 maxPriceQ96, uint256 bidBlock) = helper__seedBasedBid(bidSeed);

            // Extract scenario selections for scenario-aware verification
            PreBidScenario preBidScenario = PreBidScenario(selections[uint256(SpaceIndices.preBidScenario)]);
            PostBidScenario postBidScenario = PostBidScenario(selections[uint256(SpaceIndices.postBidScenario)]);
            console.log('Verifying with scenario - Pre:', uint256(preBidScenario));
            console.log('Verifying with scenario - Post:', uint256(postBidScenario));

            // setup pre-bid scenario
            helper__preBidScenario(preBidScenario, maxPriceQ96, true);
            console.log('preBidScenario setup complete');

            // Set the auction bidding block
            vm.roll(bidBlock);

            // Deal the caller the bid amount in ETH
            vm.deal(alice, bidAmount);
            // Submit the bid
            vm.prank(alice);
            console.log('starting users bid submission');
            usersBidStartBlock = uint64(block.number); // Store block number before submission
            usersBidId = auction.submitBid{value: bidAmount}(maxPriceQ96, bidAmount, alice, bytes(''));
            console.log('bid submitted');

            // Set up post-bid scenario using the helper
            actualPostBidScenario = helper__postBidScenario(postBidScenario, maxPriceQ96, true);
            console.log('PostBidScenario setup complete, actual scenario:', uint256(actualPostBidScenario));
        } else {
            revert('Invalid method');
        }
    }

    /**
     * @notice Comprehensive state verification function for bid submission
     * @dev Performs three layers of verification:
     *      1. Immediate post-bid: Verify all bid struct properties
     *      2. Auction-end settlement: Jump to end, exit bid, verify tokens filled
     *      3. Invariant checks: Verify auction-wide invariants hold
     *
     *      The function uses snapshot management to avoid polluting future test iterations.
     *      After jumping to auction end and verifying outcomes, it reverts to the pre-verification state.
     *
     * @param method_ The method enum value (should be submitBid)
     * @param selections The parameter selections from the design space
     */
    function verifyState(uint256 method_, uint256[] memory selections) internal {
        Method method = Method(method_);
        if (method != Method.submitBid) return;

        // Extract scenario selections for scenario-aware verification
        PreBidScenario preBidScenario = PreBidScenario(selections[uint256(SpaceIndices.preBidScenario)]);
        PostBidScenario postBidScenario = actualPostBidScenario; // Use the actual scenario that was set up

        console.log('Verifying with scenarios - Pre:', uint256(preBidScenario), 'Post:', uint256(postBidScenario));

        // ============ Phase 1: Immediate Post-Bid Verification ============
        console.log('=== Phase 1: Immediate Post-Bid Verification ===');

        // Extract original bid parameters from selections
        uint256 bidSeed = selections[uint256(SpaceIndices.bidSeed)];
        (uint128 bidAmount, uint256 maxPriceQ96,) = helper__seedBasedBid(bidSeed);

        // Verify bid struct properties
        helper__verifyBidStruct(
            usersBidId,
            alice, // owner
            maxPriceQ96, // maxPrice
            uint256(bidAmount) << FixedPoint96.RESOLUTION, // amountQ96
            usersBidStartBlock // startBlock (stored at submission time)
        );

        // Verify bid is in tick's linked list (if above clearing)
        Checkpoint memory currentCP = auction.checkpoint();
        if (maxPriceQ96 > currentCP.clearingPrice) {
            uint256 tickDemand = auction.ticks(maxPriceQ96).currencyDemandQ96;
            assertGt(tickDemand, 0, 'Tick should have demand after bid submission');
            console.log('  Tick demand updated successfully');
        }

        console.log('Phase 1 verification complete');

        // ============ Phase 2: Auction-End Settlement Verification ============
        console.log('=== Phase 2: Auction-End Settlement Verification ===');

        // Save current state for snapshot revert
        uint256 preSettlementSnapshot = vm.snapshot();

        // Jump to auction end and checkpoint
        vm.roll(auction.endBlock());
        Checkpoint memory finalCheckpoint = auction.checkpoint();
        bool graduated = auction.isGraduated();

        console.log('Auction end state:');
        console.log('  endBlock:', auction.endBlock());
        console.log('  finalClearing:', finalCheckpoint.clearingPrice);
        console.log('  graduated:', graduated);

        // Get the bid at auction end
        Bid memory finalBid = auction.bids(usersBidId);

        // SCENARIO VALIDATION: Check if actual state matches intended scenario
        helper__validateScenarioMatchesReality(postBidScenario, usersBidId, finalCheckpoint);

        // Classify exit path based on actual final state
        ExitPath exitPath = helper__classifyExitPath(finalBid, finalCheckpoint, graduated);
        console.log('Exit path:', uint256(exitPath));

        // Get owner balance before exit
        address bidOwner = finalBid.owner;
        uint256 balanceBefore = address(bidOwner).balance;

        // Verify exit based on path
        if (exitPath == ExitPath.NonGraduated) {
            console.log('Verifying NonGraduated exit path');
            uint256 expectedRefund = finalBid.amountQ96 >> FixedPoint96.RESOLUTION;
            helper__verifyNonGraduatedExit(usersBidId, balanceBefore, expectedRefund);
        } else if (exitPath == ExitPath.FullExit) {
            console.log('Verifying FullExit path');
            helper__verifyFullExit(usersBidId, balanceBefore);
        } else if (exitPath == ExitPath.PartialExit) {
            console.log('Verifying PartialExit path');

            // Detect edge cases
            uint64 lastFullyFilledBlock = helper__findLastFullyFilledCheckpoint(finalBid, finalBid.startBlock);
            uint64 outbidBlock = helper__findOutbidBlock(finalBid, finalBid.startBlock);

            if (lastFullyFilledBlock == 0) {
                console.log('  Edge case: At clearing from start (no fully-filled period)');
            }
            if (outbidBlock == finalBid.startBlock) {
                console.log('  Edge case: Outbid immediately at startBlock');
            }

            helper__verifyPartialExit(usersBidId);
        }

        console.log('Phase 2 verification complete');

        // Revert to pre-settlement state to avoid polluting future iterations
        vm.revertToState(preSettlementSnapshot);

        // ============ Phase 3: Auction Invariants Verification ============
        console.log('=== Phase 3: Auction Invariants Verification ===');

        // Invariant 1: Bid struct consistency
        Bid memory currentBid = auction.bids(usersBidId);
        assertEq(currentBid.exitedBlock, 0, 'Bid should not be exited in current timeline');
        assertTrue(currentBid.startBlock >= auction.startBlock(), 'Bid startBlock before auction start');
        assertTrue(currentBid.startBlock < auction.endBlock(), 'Bid startBlock after auction end');

        // Invariant 2: Checkpoint linked list integrity
        Checkpoint memory latestCP = auction.latestCheckpoint();
        uint64 checkpointBlock = auction.lastCheckpointedBlock();

        // Traverse backwards to verify prev pointers
        uint64 traverseBlock = checkpointBlock;
        uint256 traverseCount = 0;
        while (traverseBlock != 0 && traverseCount < CHECKPOINT_TRAVERSAL_LIMIT) {
            Checkpoint memory cp = auction.checkpoints(traverseBlock);
            if (cp.prev != 0) {
                Checkpoint memory prevCP = auction.checkpoints(cp.prev);
                assertEq(prevCP.next, traverseBlock, 'Checkpoint linked list broken');
            }
            traverseBlock = cp.prev;
            traverseCount++;
        }
        assertTrue(traverseCount < CHECKPOINT_TRAVERSAL_LIMIT, 'Checkpoint list too long');

        // Invariant 3: Clearing price monotonicity
        // Clearing price should never decrease
        Checkpoint memory bidStartCP = auction.checkpoints(currentBid.startBlock);
        assertTrue(latestCP.clearingPrice >= bidStartCP.clearingPrice, 'Clearing price decreased (should be monotonic)');

        // Invariant 4: CumulativeMps monotonicity
        assertTrue(latestCP.cumulativeMps >= bidStartCP.cumulativeMps, 'CumulativeMps should never decrease');

        // Invariant 5: Bid owner is valid address
        assertTrue(currentBid.owner != address(0), 'Bid owner should not be zero address');
        assertEq(currentBid.owner, alice, 'Bid owner should be alice');

        console.log('Phase 3 invariants verified');
        console.log('=== Verification Complete for bidId:', usersBidId, '===');
    }

    // ============ Tests ============

    function testFuzz_CombinatorialExploration(uint256 seed) public {
        Combinatorium.Handlers memory handlers = Combinatorium.Handlers({
            setupHandler: this.handleSetup,
            testHandler: this.handleTestAction,
            normalHandler: this.handleNormalAction,
            mutationHandler: this.handleMutatedAction,
            mutationSelector: this.selectMutation
        });

        ctx.runCombinatorial(seed, 10, 5, vm, handlers);
    }
}
