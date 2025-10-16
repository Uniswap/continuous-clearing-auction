// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {AuctionParameters} from '../../src/interfaces/IAuction.sol';
import {BidLib} from '../../src/libraries/BidLib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionStepsBuilder} from '../utils/AuctionStepsBuilder.sol';
import {Combinatorium} from '../utils/Combinatorium.sol';
import {FuzzBid, FuzzDeploymentParams} from '../utils/FuzzStructs.sol';

import {Test} from 'forge-std/Test.sol';

import {console} from 'forge-std/console.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

/**
 * @title AuctionSubmitBidCombinatorialTest
 * @notice Auction submit bid tests using Combinatorium library
 */
contract AuctionSubmitBidCombinatorialTest is AuctionBaseTest {
    using Combinatorium for Combinatorium.Context;

    // Auction contracts - CURRENTLY WITHIN AuctionBaseTest
    // Auction public auction;
    // ERC20Mock public token;
    // ERC20Mock public erc20Currency;
    // address public constant ETH_SENTINEL = address(0);

    Combinatorium.Context internal ctx;

    // Space indices
    enum SpaceIndices {
        method,
        bidMaxPrice,
        bidAmount,
        bidOwner,
        bidCaller,
        blockStart, // block number when the auction starts
        auctionTickSpacing, // tick spacing of the auction
        auctionFloorPrice, // floor price of the auction
        auctionSteps, // number of auction steps
        auctionStepsTime, // block time of each auction step
        blockNr, // block the action happens at - will be bound by the auction start and end block
        previousBidAmount, // previous bid amount
        previousBidsPerTick, // number of previous bids per added per previous tick
        previousBidStartTick, // previous bids will start bidding from this tick
        previousBidTickIncrement, // previous bids will increment their ticks by this amount with each step
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
    uint256 public constant MAX_BID_PRICE = 100_000 ether;

    uint256 public usersBidId;

    function setUp() public {
        console.log('setUp0');
        ctx.init(1);
        ctx.defineSpace('method', 1, 0, uint256(Method.__length) - 1);
        ctx.defineSpace('bidMaxPrice', 1, 1, MAX_BID_PRICE); // Will be lower bound by the auction floor price
        ctx.defineSpace('bidAmount', 1, MIN_BID_AMOUNT, MAX_BID_AMOUNT); // MAX AMOUNT IS SUBJECT TO CHANGE
        ctx.defineSpace('bidOwner', 1, 0, uint256(type(uint160).max));
        ctx.defineSpace('bidCaller', 1, 0, uint256(type(uint160).max));
        ctx.defineSpace('blockStart', 1, 0, type(uint32).max); // uint32 to leave room for blockEnd which needs to be uint64
        ctx.defineSpace('auctionTickSpacing', 1, 1, uint64(type(uint64).max));
        ctx.defineSpace('auctionFloorPrice', 1, 1, MAX_BID_PRICE);
        ctx.defineSpace('auctionSteps', 1, 1, type(uint8).max);
        ctx.defineSpace('auctionStepsTime', 1, 0, type(uint8).max);
        ctx.defineSpace('blockNr', 1, 0, type(uint64).max); // The exact block number will be bound by the auction start and end block
        ctx.defineSpace('previousBidAmount', 1, 1, type(uint64).max); // copied bounds from AuctionStepsBuilder.setUpBidsFuzz
        ctx.defineSpace('previousBidsPerTick', 1, 0, 10);
        ctx.defineSpace('previousBidStartTick', 1, 1, type(uint8).max - 55); // 55 IS AN ARBITRARY NUMBER Right NOW. GIVING SPACE FOR INCREMENTS.
        ctx.defineSpace('previousBidTickIncrement', 1, 0, 20); // 20 IS AN ARBITRARY NUMBER Right NOW.
        ctx.defineSpace('mutationRandomness', 1, 0, type(uint256).max - 1);
        console.log('setUp1');
    }

    // ============ Handlers ============

    function handleSetup(uint256 step, uint256[] memory selections) external returns (bool) {
        console.log('handleSetup');

        if (step == 0) {
            uint40 blockDelta = uint40(selections[uint256(SpaceIndices.auctionStepsTime)]);
            uint40 numberOfSteps = uint40(selections[uint256(SpaceIndices.auctionSteps)]);
            uint256 blockStart = selections[uint256(SpaceIndices.blockStart)];
            uint256 blockEnd = blockStart + (numberOfSteps * blockDelta);
            bytes memory auctionStepsData_ = AuctionStepsBuilder.splitEvenlyAmongSteps(numberOfSteps, blockDelta);

            FuzzDeploymentParams memory params_ = FuzzDeploymentParams({
                totalSupply: TOTAL_SUPPLY,
                auctionParams: AuctionParameters({
                    currency: address(0),
                    tokensRecipient: address(0),
                    fundsRecipient: address(0),
                    startBlock: uint64(blockStart),
                    endBlock: uint64(blockEnd),
                    claimBlock: uint64(blockEnd),
                    tickSpacing: selections[uint256(SpaceIndices.auctionTickSpacing)],
                    validationHook: address(0),
                    floorPrice: selections[uint256(SpaceIndices.auctionFloorPrice)],
                    requiredCurrencyRaised: 0,
                    auctionStepsData: auctionStepsData_
                }),
                numberOfSteps: uint8(numberOfSteps)
            });
            setUpAuction(params_);
            console.log('auction: tickSpacing', auction.tickSpacing());
            console.log('auction: floorPrice', auction.floorPrice());

            // Move to the auction start block
            vm.roll(blockStart);

            return true;
        }

        // Handle advanced setups for steps > 0

        if (selections[uint256(SpaceIndices.method)] == uint256(Method.submitBid)) {
            uint8 previousBidStartTick = uint8(selections[uint256(SpaceIndices.previousBidStartTick)]);
            uint256 previousBidTickIncrement = selections[uint256(SpaceIndices.previousBidTickIncrement)] * step;
            uint64 previousBidAmount = uint64(selections[uint64(SpaceIndices.previousBidAmount)]);
            // _bound(selections[uint64(SpaceIndices.previousBidAmount)], BidLib.MIN_BID_AMOUNT, type(uint64).max));
            uint256 previousBidsPerTick = selections[uint256(SpaceIndices.previousBidsPerTick)];

            FuzzBid memory bid = FuzzBid({
                bidAmount: uint64(_bound(previousBidAmount, MIN_BID_AMOUNT, type(uint64).max)),
                tickNumber: previousBidStartTick // uint8(previousBidStartTick + previousBidTickIncrement)
            });

            for (uint256 i = 0; i < 1; /* previousBidsPerTick */ i++) {
                console.log('trying to submit bid');
                console.log('previousBidStartTick', previousBidStartTick);
                console.log('previousBidTickIncrement', previousBidTickIncrement);
                console.log('previousBidAmount', previousBidAmount);
                console.log('previousBidsPerTick', previousBidsPerTick);
                (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(i, bid, OTHER_BIDS_OWNER);
                console.log('bidPlaced', bidPlaced);
                if (bidPlaced) {
                    console.log('bidPlaced with id', bidId);
                }
            }
        }

        return true;
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

        address owner = address(uint160(selections[uint256(SpaceIndices.bidOwner)]));
        address caller = address(uint160(selections[uint256(SpaceIndices.bidCaller)]));
        uint256 tickSpacing = auction.tickSpacing();
        uint128 bidAmount = uint128(selections[uint256(SpaceIndices.bidAmount)]);
        uint256 maxPrice = helper__roundPriceDownToTickSpacing(
            bound(selections[uint256(SpaceIndices.bidMaxPrice)], auction.floorPrice() + tickSpacing, MAX_BID_PRICE),
            tickSpacing
        );
        if (method == Method.submitBid) {
            if (mutation.mutationType == Combinatorium.MutationType.WRONG_PARAMETER) {
                uint256 mutationRandomness = uint256(selections[uint256(SpaceIndices.mutationRandomness)]) % 2;

                // Set the auction bidding block
                uint256 blockNumber =
                    bound(selections[uint256(SpaceIndices.blockNr)], auction.startBlock(), auction.endBlock() - 1);
                vm.roll(blockNumber);

                // Deal the caller the bid amount in ETH
                vm.deal(caller, bidAmount);
                // Prank the caller
                vm.prank(caller);
                if (mutationRandomness == 0) {
                    // value sent not matching the amount
                    try auction.submitBid{value: bidAmount - 1}(maxPrice, bidAmount, owner, bytes('')) {
                        return true;
                    } catch {
                        return false;
                    }
                } else if (mutationRandomness == 1 && tickSpacing > 1) {
                    // maxPrice not matching the tickSpacking
                    maxPrice = tickSpacing + 1;
                    try auction.submitBid{value: bidAmount}(maxPrice, bidAmount, owner, bytes('')) {
                        return true;
                    } catch {
                        return false;
                    }
                }
            }
        }

        return true; // THIS WILL FAIL ALL OTHER MUTATIONS

        // } else if (mutation.mutationType == Combinatorium.MutationType.INVALID_STATE) {
        //     counter.lock();
        //     try counter.setNumber(123) {
        //         return true;
        //     } catch {
        //         return false;
        //     }
        // } else if (mutation.mutationType == Combinatorium.MutationType.SKIP_CALL) {
        //     counter.unlock();
        //     vm.store(address(counter), bytes32(uint256(1)), bytes32(uint256(0)));
        //     try counter.multiplyNumber() {
        //         return true;
        //     } catch {
        //         return false;
        //     }
        // }
        // return false;
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

        address owner = address(uint160(selections[uint256(SpaceIndices.bidOwner)]));
        address caller = address(uint160(selections[uint256(SpaceIndices.bidCaller)]));
        uint256 tickSpacing = auction.tickSpacing();
        uint128 bidAmount = uint128(selections[uint256(SpaceIndices.bidAmount)]);
        uint256 maxPrice = helper__roundPriceDownToTickSpacing(
            bound(selections[uint256(SpaceIndices.bidMaxPrice)], auction.floorPrice() + tickSpacing, MAX_BID_PRICE),
            tickSpacing
        );

        if (method == Method.submitBid) {
            console.log('maxPrice', maxPrice);
            console.log('bidAmount', bidAmount);
            console.log('owner', owner);
            console.log('caller', caller);

            // Set the auction bidding block
            uint256 blockNumber =
                bound(selections[uint256(SpaceIndices.blockNr)], auction.startBlock(), auction.endBlock() - 1);
            vm.roll(blockNumber);

            // Deal the caller the bid amount in ETH
            vm.deal(caller, bidAmount);
            // Prank the caller
            vm.prank(caller);
            usersBidId = auction.submitBid{value: bidAmount}(maxPrice, bidAmount, owner, bytes(''));
        } else {
            revert('Invalid method');
        }
    }

    function verifyState(uint256 method_, uint256[] memory selections) internal view {
        Method method = Method(method_);
        if (method == Method.submitBid) {
            assertEq(auction.nextBidId(), usersBidId + 1);
            assertEq(
                auction.bids(usersBidId).amountQ96 >> FixedPoint96.RESOLUTION,
                selections[uint256(SpaceIndices.bidAmount)]
            );
        }
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

    // function testFuzz_IncrementThenMultiply(uint256 setupSeed, uint256 mult) public {
    //     mult = bound(mult, 1, 100);

    //     ctx.executeSetup(setupSeed, vm, this.handleSetup);

    //     uint256 preValue = counter.number();

    //     counter.unlock();
    //     counter.setMultiplier(mult);
    //     counter.increment();
    //     counter.multiplyNumber();

    //     assertEq(counter.number(), (preValue + 1) * mult);
    // }
}
