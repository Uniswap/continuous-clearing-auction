// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {AuctionParameters} from '../../src/interfaces/IAuction.sol';
import {Bid} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';

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
    using ValueX7Lib for ValueX7;

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

    uint256 public seed;
    uint256 public usersBidId;
    uint64 public usersBidStartBlock; // Track the block where bid was submitted
    PostBidScenario public actualPostBidScenario; // Track the actual post-bid scenario

    // Phase 1 Metrics Storage (populated by verifyState, consumed by documentState)
    uint256 private metrics_fillRatioPercent;
    string private metrics_partialFillReason;
    uint256 private metrics_bidLifetimeBlocks;
    uint256 private metrics_blocksFromStart;
    uint256 private metrics_timeToOutbid;
    bool private metrics_wasOutbid;
    bool private metrics_neverFullyFilled;
    bool private metrics_nearGraduationBoundary;
    uint256 private metrics_clearingPriceStart;
    uint256 private metrics_clearingPriceEnd;
    uint256 private metrics_tokensReceived;
    uint256 private metrics_pricePerTokenETH;
    bool private metrics_didGraduate;
    // Auction context metrics
    uint64 private metrics_auctionStartBlock;
    uint64 private metrics_auctionDurationBlocks;
    uint256 private metrics_floorPrice;
    uint256 private metrics_tickSpacing;
    uint256 private metrics_totalSupply;

    // Coverage tracking event
    event CoverageData(uint8 preBidScenario, uint8 postBidScenario, uint128 bidAmount, uint256 maxPrice);

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
            documentState(selections);
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
                (uint128 bidAmount, uint256 maxPriceQ96, uint256 bidBlock,) = helper__seedBasedBid(bidSeed);

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

            // setup pre-bid scenario
            {
                PreBidScenario preBidScenario = PreBidScenario(selections[uint256(SpaceIndices.preBidScenario)]);
                console.log('Verifying with scenario - Pre:', uint256(preBidScenario));
                (, uint256 maxPriceQ96,,) = helper__seedBasedBid(bidSeed);
                helper__preBidScenario(preBidScenario, maxPriceQ96, true);
                console.log('preBidScenario setup complete');
            }

            // Set the auction bidding block
            {
                (uint128 bidAmount, uint256 maxPriceQ96, uint256 bidBlock,) = helper__seedBasedBid(bidSeed);
                vm.roll(bidBlock);

                // Deal the caller the bid amount in ETH
                vm.deal(alice, bidAmount);
                // Submit the bid
                vm.prank(alice);
                console.log('starting users bid submission');
                usersBidStartBlock = uint64(block.number); // Store block number before submission
                usersBidId = auction.submitBid{value: bidAmount}(maxPriceQ96, bidAmount, alice, bytes(''));
                console.log('bid submitted');
            }

            // Set up post-bid scenario using the helper
            {
                (, uint256 maxPriceQ96, uint256 bidBlock, uint64 furtherBidsDelay) = helper__seedBasedBid(bidSeed);
                // TEMP: fixed furtherBidsDelay to mid auction
                furtherBidsDelay = uint64((auction.endBlock() - bidBlock) / 2);
                PostBidScenario postBidScenario = PostBidScenario(selections[uint256(SpaceIndices.postBidScenario)]);
                // TEMP: fixed postBidScenario to UserOutbidLater
                postBidScenario = PostBidScenario.UserAtClearing;
                console.log('Verifying with scenario - Post:', uint256(postBidScenario));
                uint256 clearingPriceFillPercentage = 0;
                if (postBidScenario == PostBidScenario.UserAtClearing) {
                    clearingPriceFillPercentage =
                        uint256(keccak256(abi.encodePacked(seed, 'bid.clearingPriceFillPercentage')));
                    clearingPriceFillPercentage = bound(clearingPriceFillPercentage, 0, ConstantsLib.MPS - 1);
                }
                actualPostBidScenario = helper__postBidScenario(
                    postBidScenario, maxPriceQ96, true, furtherBidsDelay, clearingPriceFillPercentage
                );
                console.log('PostBidScenario setup complete, actual scenario:', uint256(actualPostBidScenario));
            }
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
        (uint128 bidAmount, uint256 maxPriceQ96,,) = helper__seedBasedBid(bidSeed);

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

        // Track currency spent for accurate fill ratio calculation
        uint256 currencySpentQ96 = 0;

        // Verify exit based on path
        if (exitPath == ExitPath.NonGraduated) {
            console.log('Verifying NonGraduated exit path');
            uint256 expectedRefund = finalBid.amountQ96 >> FixedPoint96.RESOLUTION;
            helper__verifyNonGraduatedExit(usersBidId, balanceBefore, expectedRefund);
            currencySpentQ96 = 0; // No currency spent for non-graduated
        } else if (exitPath == ExitPath.FullExit) {
            console.log('Verifying FullExit path');
            currencySpentQ96 = helper__verifyFullExit(usersBidId, balanceBefore);
        } else if (exitPath == ExitPath.PartialExit) {
            console.log('Verifying PartialExit path');
            currencySpentQ96 = helper__verifyPartialExit(usersBidId);
        }

        console.log('Phase 2 verification complete');

        // Capture tokens filled from bid struct after exit (bid was exited by verification helpers)
        Bid memory exitedBid = auction.bids(usersBidId);
        uint256 tokensFilled = exitedBid.tokensFilled;

        // ============ Phase 1 Metrics Collection (BEFORE snapshot revert) ============
        // Collect metrics from Phase 2 state BEFORE reverting
        // Store in memory to survive the revert
        (
            uint256 fillRatioPercent,
            string memory partialFillReason,
            uint256 bidLifetimeBlocks,
            uint256 blocksFromStart,
            uint256 timeToOutbid,
            bool wasOutbid,
            bool neverFullyFilled,
            bool nearGraduationBoundary,
            uint256 clearingPriceStart,
            uint256 clearingPriceEnd,
            uint256 tokensReceived,
            uint256 pricePerTokenETH,
            bool didGraduate,
            uint64 auctionStartBlock,
            uint64 auctionDurationBlocks,
            uint256 floorPrice,
            uint256 tickSpacing,
            uint256 totalSupply_
        ) = _computePhase1Metrics(finalBid, finalCheckpoint, exitPath, graduated, tokensFilled, currencySpentQ96);

        // Revert to pre-settlement state to avoid polluting future iterations
        vm.revertToState(preSettlementSnapshot);

        // Store metrics in storage AFTER revert so they persist for documentState()
        metrics_fillRatioPercent = fillRatioPercent;
        metrics_partialFillReason = partialFillReason;
        metrics_bidLifetimeBlocks = bidLifetimeBlocks;
        metrics_blocksFromStart = blocksFromStart;
        metrics_timeToOutbid = timeToOutbid;
        metrics_wasOutbid = wasOutbid;
        metrics_neverFullyFilled = neverFullyFilled;
        metrics_nearGraduationBoundary = nearGraduationBoundary;
        metrics_clearingPriceStart = clearingPriceStart;
        metrics_clearingPriceEnd = clearingPriceEnd;
        metrics_tokensReceived = tokensReceived;
        metrics_pricePerTokenETH = pricePerTokenETH;
        metrics_didGraduate = didGraduate;
        metrics_auctionStartBlock = auctionStartBlock;
        metrics_auctionDurationBlocks = auctionDurationBlocks;
        metrics_floorPrice = floorPrice;
        metrics_tickSpacing = tickSpacing;
        metrics_totalSupply = totalSupply_;

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
        Checkpoint memory currentBidStartCP = auction.checkpoints(currentBid.startBlock);
        assertTrue(
            latestCP.clearingPrice >= currentBidStartCP.clearingPrice, 'Clearing price decreased (should be monotonic)'
        );

        // Invariant 4: CumulativeMps monotonicity
        assertTrue(latestCP.cumulativeMps >= currentBidStartCP.cumulativeMps, 'CumulativeMps should never decrease');

        // Invariant 5: Bid owner is valid address
        assertTrue(currentBid.owner != address(0), 'Bid owner should not be zero address');
        assertEq(currentBid.owner, alice, 'Bid owner should be alice');

        console.log('Phase 3 invariants verified');
        console.log('=== Verification Complete for bidId:', usersBidId, '===');
    }

    /**
     * @notice Compute Phase 1 metrics from auction-end state
     * @dev Returns metrics as memory values that survive snapshot revert
     * @dev Uses actualPostBidScenario as the SOURCE OF TRUTH for outbid status
     * @param finalBid The bid struct at auction end
     * @param finalCheckpoint The checkpoint at auction end
     * @param exitPath The classified exit path
     * @param graduated Whether the auction graduated
     * @param tokensFilled Tokens filled by the bid
     * @param currencySpentQ96 Actual currency spent in Q96 format
     */
    function _computePhase1Metrics(
        Bid memory finalBid,
        Checkpoint memory finalCheckpoint,
        ExitPath exitPath,
        bool graduated,
        uint256 tokensFilled,
        uint256 currencySpentQ96
    )
        private
        view
        returns (
            uint256 fillRatioPercent,
            string memory partialFillReason,
            uint256 bidLifetimeBlocks,
            uint256 blocksFromStart,
            uint256 timeToOutbid,
            bool wasOutbid,
            bool neverFullyFilled,
            bool nearGraduationBoundary,
            uint256 clearingPriceStart,
            uint256 clearingPriceEnd,
            uint256 tokensReceived,
            uint256 pricePerTokenETH,
            bool didGraduate,
            uint64 auctionStartBlock,
            uint64 auctionDurationBlocks,
            uint256 floorPrice,
            uint256 tickSpacing,
            uint256 totalSupply
        )
    {
        // Step 1: Fill Ratio Metrics (ACCURATE CALCULATION)
        // fillRatio = (currencySpentQ96 / originalBidAmountQ96) * 100
        if (exitPath == ExitPath.FullExit) {
            fillRatioPercent = 100;
            partialFillReason = 'full';
        } else if (exitPath == ExitPath.NonGraduated) {
            fillRatioPercent = 0;
            partialFillReason = 'non_graduated';
        } else {
            // PartialExit - Calculate actual fill ratio
            if (finalBid.amountQ96 > 0) {
                // Calculate fill ratio with high precision (basis points)
                // Multiply by 10_000 first to get 2 decimal places
                uint256 fillRatioBasisPoints = (currencySpentQ96 * 10_000) / finalBid.amountQ96;
                // Convert to percentage (divide by 100 to get 0-100 range with 2 decimals)
                fillRatioPercent = fillRatioBasisPoints / 100;
                console.log('  fillRatioBasisPoints:', fillRatioBasisPoints);
                console.log('  finalBid.amountQ96:', finalBid.amountQ96);
                console.log('  currencySpentQ96:', currencySpentQ96);
                console.log('  fillRatioPercent:', fillRatioPercent);
                console.log('  finalBid.startBlock:', finalBid.startBlock);
                console.log('  auction.startBlock():', auction.startBlock());
                console.log('  auction.endBlock():', auction.endBlock());
                (uint64 lastFullyFilledBlock, uint64 notFullyFilledBlock, bool notFullyFilled) =
                    helper__findLastFullyFilledCheckpoint(finalBid);
                console.log('  lastFullyFilledBlock:', lastFullyFilledBlock);
                console.log('  notFullyFilledBlock:', notFullyFilledBlock);
                console.log('  notFullyFilled:', notFullyFilled);
                (uint64 outbidBlock, bool wasOutbid) = helper__findOutbidBlock(finalBid);
                console.log('  outbidBlock:', outbidBlock);
                console.log('  wasOutbid:', wasOutbid);
                Checkpoint memory finalCP = auction.checkpoints(auction.endBlock());
                console.log('  finalCP.clearingPrice:', finalCP.clearingPrice);
                console.log('  finalCP.cumulativeMps:', finalCP.cumulativeMps);
                console.log('  finalCP.cumulativeMpsPerPrice:', finalCP.cumulativeMpsPerPrice);
                console.log('  finalCP.prev:', finalCP.prev);
                console.log('  finalCP.next:', finalCP.next);
                console.log('  finalCP.prev:', finalCP.prev);
                revert('test');
            } else {
                fillRatioPercent = 0;
            }
            partialFillReason = graduated ? 'partial_graduated' : 'partial_outbid';
        }

        // Step 2: Timing Metrics - USE POSTBIDSCENARIO AS SOURCE OF TRUTH
        // The PostBidScenario enum accurately represents what actually happened
        bidLifetimeBlocks = finalBid.exitedBlock > 0
            ? finalBid.exitedBlock - finalBid.startBlock
            : auction.endBlock() - finalBid.startBlock;
        blocksFromStart = finalBid.startBlock - auction.startBlock();

        // Find the block where the bid was outbid
        (uint64 outbidBlock, bool wasOutbid_) = helper__findOutbidBlock(finalBid);
        wasOutbid = wasOutbid_;
        timeToOutbid = wasOutbid_ ? outbidBlock - finalBid.startBlock : 0;

        // Step 3: Edge Case Flags
        neverFullyFilled = (fillRatioPercent < 100);
        nearGraduationBoundary =
            !graduated && (block.number - auction.startBlock() > (auction.endBlock() - auction.startBlock()) * 90 / 100);

        // Step 4: Price Analysis Metrics
        clearingPriceStart = auction.checkpoints(finalBid.startBlock).clearingPrice;
        clearingPriceEnd = finalCheckpoint.clearingPrice;

        // Step 5: Token Output Metrics
        // Tokens received from the bid struct (set by exitBid)
        tokensReceived = tokensFilled;

        // Calculate price per token in ETH (wei)
        // pricePerToken = actualCurrencySpent / tokensReceived
        uint256 currencySpent = currencySpentQ96 >> FixedPoint96.RESOLUTION;
        if (tokensReceived > 0) {
            pricePerTokenETH = (currencySpent * 1e18) / tokensReceived;
        } else {
            pricePerTokenETH = 0;
        }

        // Step 6: Graduation Tracking
        didGraduate = graduated;

        // Step 7: Auction Context Info
        auctionStartBlock = auction.startBlock();
        auctionDurationBlocks = auction.endBlock() - auction.startBlock();
        floorPrice = auction.floorPrice();
        tickSpacing = auction.tickSpacing();
        totalSupply = auction.totalSupply();
    }

    /**
     * @notice Document test case coverage data
     * @dev Lightweight function to log test parameters without complex stack operations
     * @param selections The parameter selections from the design space
     */
    function documentState(uint256[] memory selections) internal {
        // Extract basic scenario info
        PreBidScenario preBid = PreBidScenario(selections[uint256(SpaceIndices.preBidScenario)]);
        PostBidScenario postBid = actualPostBidScenario;

        // Get bid parameters
        uint256 bidSeed = selections[uint256(SpaceIndices.bidSeed)];
        (uint128 bidAmount, uint256 maxPrice,,) = helper__seedBasedBid(bidSeed);

        // Emit event for coverage tracking
        emit CoverageData(uint8(preBid), uint8(postBid), bidAmount, maxPrice);

        // Write to file for aggregation across all fuzz runs (new format with auction context)
        string memory coverageLine = string(
            abi.encodePacked(
                // Original 4 columns
                vm.toString(uint256(preBid)),
                ',',
                vm.toString(uint256(postBid)),
                ',',
                vm.toString(uint256(bidAmount)),
                ',',
                vm.toString(maxPrice),
                ',',
                // Fill ratio metrics
                vm.toString(metrics_fillRatioPercent),
                ',',
                metrics_partialFillReason,
                ',',
                // Timing metrics
                vm.toString(metrics_bidLifetimeBlocks),
                ',',
                vm.toString(metrics_blocksFromStart),
                ',',
                vm.toString(metrics_timeToOutbid),
                ',',
                // Outbid status flags
                metrics_wasOutbid ? 'true' : 'false',
                ',',
                metrics_neverFullyFilled ? 'true' : 'false',
                ',',
                metrics_nearGraduationBoundary ? 'true' : 'false',
                ',',
                // Price analysis
                vm.toString(metrics_clearingPriceStart),
                ',',
                vm.toString(metrics_clearingPriceEnd),
                ',',
                // Token output metrics
                vm.toString(metrics_tokensReceived),
                ',',
                vm.toString(metrics_pricePerTokenETH),
                ',',
                // Graduation tracking
                metrics_didGraduate ? 'true' : 'false',
                ',',
                // Auction context
                vm.toString(uint256(metrics_auctionStartBlock)),
                ',',
                vm.toString(uint256(metrics_auctionDurationBlocks)),
                ',',
                vm.toString(metrics_floorPrice),
                ',',
                vm.toString(metrics_tickSpacing),
                ',',
                vm.toString(metrics_totalSupply),
                '\n'
            )
        );
        vm.writeLine('./coverage_data.csv', coverageLine);
    }

    // ============ Tests ============

    function testFuzz_CombinatorialExploration(uint256 seed_) public {
        seed = seed_;
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
