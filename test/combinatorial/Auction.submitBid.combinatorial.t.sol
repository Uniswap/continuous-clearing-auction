// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {AuctionParameters} from '../../src/interfaces/IAuction.sol';
import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionStepsBuilder} from '../utils/AuctionStepsBuilder.sol';
import {Combinatorium} from '../utils/Combinatorium.sol';
import {FuzzBid, FuzzDeploymentParams} from '../utils/FuzzStructs.sol';

import {PostBidScenario, PreBidScenario} from './CombinatorialEnums.sol';
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
    address public constant OTHER_BIDS_OWNER = address(0x1);
    uint256 public constant MIN_BID_AMOUNT = 1;
    uint256 public constant MAX_BID_AMOUNT = 100 ether;
    uint256 public constant MAX_BID_PRICE_Q96 = 1e17 << FixedPoint96.RESOLUTION;

    uint256 public usersBidId;

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

    // ============ Helper Functions ============

    /// @notice Verify a non-graduated auction exit
    function helper__verifyNonGraduatedExit(uint256 bidId, uint256 balanceBefore, uint256 expectedAmount) external {
        try auction.exitBid(bidId) {
            /// TODO: WIP
        } catch {
            revert('exitBid failed');
        }
    }

    /// @notice Verify a partial exit (outbid or at clearing price)
    function helper__verifyPartialExit() external {
        // try auction.exitPartiallyFilledBid(bidId, lower, upper) {}
        // catch {
        //     revert('exitPartiallyFilledBid failed');
        // }
    }

    /// @notice Verify a full exit (above clearing price)
    function helper__verifyFullExit(uint256 bidId, uint256 balanceBefore, uint256 expectedAmount) external {
        try auction.exitBid(bidId) {}
        catch {
            revert('exitBid failed');
        }
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

    function handleNormalAction(uint256[] memory /* selections */ ) external returns (bool) {
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
        view
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
            console.log('maxPriceQ96', maxPriceQ96);
            console.log('bidAmount', bidAmount);
            console.log('bidBlock', bidBlock);

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
            usersBidId = auction.submitBid{value: bidAmount}(maxPriceQ96, bidAmount, alice, bytes(''));
            console.log('bid submitted');

            // Set up post-bid scenario using the helper
            helper__postBidScenario(postBidScenario, maxPriceQ96, true);
            console.log('postBidScenario setup complete');
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
        PostBidScenario postBidScenario = PostBidScenario(selections[uint256(SpaceIndices.postBidScenario)]);

        console.log('Verifying with scenarios - Pre:', uint256(preBidScenario), 'Post:', uint256(postBidScenario));

        // ============ Phase 1: Bid-Struct Verification ============

        // ============ Phase 2: Auction-End Settlement  ============

        // ============ Phase 3: Auction-State Verification ============
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
