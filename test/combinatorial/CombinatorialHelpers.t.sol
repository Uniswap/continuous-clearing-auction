// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';

import {Bid} from '../../src/libraries/BidLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';

import {FuzzBid} from '../utils/FuzzStructs.sol';

import {PostBidScenario, PreBidScenario} from './CombinatorialEnums.sol';
import {CombinatorialHelpers} from './CombinatorialHelpers.sol';

import {Test} from 'forge-std/Test.sol';
import {console2} from 'forge-std/console2.sol';

contract CombinatorialHelpersTest is CombinatorialHelpers {
    function _legalizeBidMaxPrice(uint256 maxPrice, bool Q96) internal view returns (uint64 targetClearingPrice) {
        uint256 auctionTickSpacing = Q96 ? auction.tickSpacing() : auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        console2.log('auctionTickSpacing', auctionTickSpacing);

        uint256 targetClearingPriceTemp = helper__roundPriceUpToTickSpacing(maxPrice, auctionTickSpacing);
        targetClearingPrice = uint64(bound(targetClearingPriceTemp, 1, Q96 ? type(uint256).max : 1e17));

        console2.log('rounded targetClearingPrice', targetClearingPrice);

        return targetClearingPrice;
    }

    function setUp() public virtual {
        setUpAuction();
    }

    function test_combinatorial_helpers_postBidScenario(FuzzBid memory bid, uint8 scenarioSelection) public {
        vm.assume(bid.bidAmount > 0);
        vm.assume(bid.tickNumber > 0);

        auction.checkpoint();
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        console2.log('tickSpacing:', tickSpacing);
        console2.log('floorPrice:', floorPrice);
        console2.log('clearingPrice original:', clearingPrice);
        // -- Tests with fixed values --
        // bid.bidAmount = 1 ether;
        // bid.tickNumber = 20;

        console2.log('bid.tickNumber:', bid.tickNumber);

        PostBidScenario scenario = PostBidScenario(scenarioSelection % uint256(PostBidScenario.__length));

        uint256 maxPrice =
            helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(bid.tickNumber) >> FixedPoint96.RESOLUTION;
        vm.deal(address(this), inputAmountForTokens(bid.bidAmount, maxPrice << FixedPoint96.RESOLUTION));
        (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(0, bid, alice);
        console2.log('bidPlaced:', bidPlaced);
        if (!bidPlaced) {
            revert('requires a bid to be placed');
        }

        Bid memory bidOnChain = auction.bids(bidId);
        assertEq(bidOnChain.maxPrice >> FixedPoint96.RESOLUTION, maxPrice);

        console2.log('Scenario:', uint256(scenario));
        console2.log('User max price:', maxPrice);
        console2.log('clearingPrice before Scenario:', auction.clearingPrice() >> FixedPoint96.RESOLUTION);
        helper__postBidScenario(scenario, maxPrice, false);
        console2.log('clearingPrice after Scenario:', auction.clearingPrice() >> FixedPoint96.RESOLUTION);

        // Verify
        vm.roll(block.number + 1);
        auction.checkpoint();
        if (scenario == PostBidScenario.NoBidsAfterUser) {
            // Ensure no bid after the users
            assertEq(auction.bids(bidId + 1).maxPrice, 0);
        } else if (scenario == PostBidScenario.UserAboveClearing) {
            if (auction.bids(bidId + 1).maxPrice != 0) {
                console2.log('auction.clearingPrice()', auction.clearingPrice() >> FixedPoint96.RESOLUTION);
                console2.log('bidOnChain.maxPrice', bidOnChain.maxPrice >> FixedPoint96.RESOLUTION);
                assertTrue(
                    auction.clearingPrice() < bidOnChain.maxPrice,
                    'clearingPrice should be smaller than the users maxPrice'
                );
            }
        } else if (scenario == PostBidScenario.UserAtClearing) {
            assertTrue(
                auction.clearingPrice() >> FixedPoint96.RESOLUTION == maxPrice,
                'clearingPrice should be equal to maxPrice'
            );
        } else if (scenario == PostBidScenario.UserOutbidLater) {
            assertTrue(
                bidOnChain.startBlock < auction.bids(bidId + 1).startBlock,
                'startBlock should be less than next startBlock'
            );
            assertTrue(
                auction.clearingPrice() >> FixedPoint96.RESOLUTION > maxPrice,
                'clearingPrice should be greater than maxPrice'
            );
        } else if (scenario == PostBidScenario.UserOutbidImmediately) {
            assertTrue(
                auction.bids(bidId).startBlock == auction.bids(bidId + 1).startBlock, 'startBlock should be equal'
            );
            assertTrue(
                auction.clearingPrice() >> FixedPoint96.RESOLUTION > maxPrice,
                'clearingPrice should be greater than maxPrice'
            );
        } else {
            revert('Invalid post bid scenario');
        }
    }

    function test_combinatorial_helpers_preBidScenario(FuzzBid memory bid, uint8 scenarioSelection) public {
        auction.checkpoint();
        uint256 clearingPriceOriginal = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        console2.log('tickSpacing:', tickSpacing);
        console2.log('floorPrice:', floorPrice);
        console2.log('clearingPrice original:', clearingPriceOriginal);

        // -- Tests with fixed values --
        // bid.bidAmount = 1 ether;
        // bid.tickNumber = 20;
        // scenarioSelection = 1;

        console2.log('bid.tickNumber:', bid.tickNumber);

        PreBidScenario scenario = PreBidScenario(scenarioSelection % uint256(PreBidScenario.__length));

        uint256 maxPrice =
            helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(bid.tickNumber) >> FixedPoint96.RESOLUTION;
        if (maxPrice <= floorPrice || bid.tickNumber == 0) {
            // Invalid maxPrice or tickNumber
            return;
        }

        console2.log('Scenario:', uint256(scenario));
        console2.log('User max price:', maxPrice);
        console2.log('clearingPrice before Scenario:', auction.clearingPrice() >> FixedPoint96.RESOLUTION);

        // Setup the pre-bid scenario
        helper__preBidScenario(scenario, maxPrice, false);

        uint256 clearingPriceAfterScenario = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        console2.log('clearingPrice after Scenario:', clearingPriceAfterScenario);

        // Now place the user's bid
        vm.deal(address(this), inputAmountForTokens(bid.bidAmount, maxPrice << FixedPoint96.RESOLUTION));
        (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(0, bid, alice);
        console2.log('bidPlaced:', bidPlaced);

        if (!bidPlaced) {
            revert('Bid should be placed when maxPrice is above floorPrice');
        }
        assertEq(auction.bids(bidId).maxPrice >> FixedPoint96.RESOLUTION, maxPrice);

        // Verify the scenario was set up correctly
        if (scenario == PreBidScenario.NoBidsBeforeUser) {
            assertEq(clearingPriceAfterScenario, clearingPriceOriginal);
            assertTrue(bidPlaced, 'Bid should be placed when no bids before user');
        } else if (scenario == PreBidScenario.BidsBeforeUser) {
            if (maxPrice > floorPrice + tickSpacing * 2) {
                assertTrue(
                    auction.bids(bidId - 1).maxPrice != 0, 'Bid should be placed when clearing is below maxPrice'
                );
                assertTrue(
                    clearingPriceAfterScenario < maxPrice - tickSpacing,
                    'Clearing price should be below maxPrice - tickSpacing'
                );
            } else {
                assertTrue(clearingPriceAfterScenario == clearingPriceOriginal);
                assertTrue(
                    auction.bids(bidId + 1).maxPrice == 0, 'Bid should not be placed when clearing is below floorPrice'
                );
            }
        } else if (scenario == PreBidScenario.ClearingPriceBelowMaxPrice) {
            assertEq(clearingPriceAfterScenario, maxPrice - tickSpacing);
        } else if (scenario == PreBidScenario.BidsAtClearingPrice) {
            // Clearing should be one tick below maxPrice, but there's a bid at maxPrice
            assertEq(clearingPriceAfterScenario, maxPrice - tickSpacing);
            // Verify there's already a bid at the user's maxPrice
            // The user's bid will compete at the same price level
        } else {
            revert('Invalid pre bid scenario');
        }
    }

    // function test_cumulativeMPS() public {
    //     Checkpoint memory checkpoint1 = auction.checkpoint();
    //     console2.log("After block 1:");
    //     console2.log("  clearingPrice:", checkpoint1.clearingPrice);
    //     console2.log("  cumulativeMps:", checkpoint1.cumulativeMps);
    //     console2.log("  cumulativeMpsPerPrice:", checkpoint1.cumulativeMpsPerPrice);

    //     vm.roll(block.number + 1);
    //     Checkpoint memory checkpoint2 = auction.checkpoint();
    //     console2.log("After block 2:");
    //     console2.log("  clearingPrice:", checkpoint2.clearingPrice);
    //     console2.log("  cumulativeMps:", checkpoint2.cumulativeMps);
    //     console2.log("  cumulativeMpsPerPrice:", checkpoint2.cumulativeMpsPerPrice);

    //     // Calculate the ratio
    //     console2.log("Ratio (cumulativeMpsPerPrice / clearingPrice):");
    //     uint256 ratio = (checkpoint2.cumulativeMpsPerPrice * 1e18) / checkpoint2.clearingPrice;
    //     console2.log("  ", ratio);

    //     // Calculate deltaMps per block
    //     console2.log("deltaMps per block:", checkpoint2.cumulativeMps / 1);
    //     console2.log("Total blocks in auction:", auction.endBlock() - auction.startBlock());
    // }

    function test_combinatorial_helpers_setAuctionClearingPrice(uint64 targetClearingPrice) public {
        // uint128 targetClearingPrice = 1e17;

        uint128 legalizedTargetClearingPrice = _legalizeBidMaxPrice(targetClearingPrice, false);

        // Move the clearing price to the target price
        address[] memory bidOwners = new address[](3);
        bidOwners[0] = address(this);
        bidOwners[0] = alice;
        bidOwners[0] = bob;
        bool success = helper__setAuctionClearingPrice(legalizedTargetClearingPrice, bidOwners, false);

        // Not successful if clearing price is greater then target, since the price can only go up
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        if (clearingPrice < floorPrice) {
            clearingPrice = floorPrice;
        }
        console2.log('adjusted clearingPrice', clearingPrice);

        if (clearingPrice > legalizedTargetClearingPrice) {
            assertFalse(success);
            return;
        }
        assertTrue(success);
        assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, legalizedTargetClearingPrice);
    }

    function test_combinatorial_helpers_setAuctionClearingPrice_withPriorBid(
        uint64 targetClearingPrice,
        uint8 priorBidTargetTick
    ) public {
        // -- Pre bid setup --
        // previously move up the auction clearing price by a random amount of ticks:
        // priorBidTargetTick = 1;
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint128 priorBidMaxPrice =
            uint128((auction.floorPrice() >> FixedPoint96.RESOLUTION) + (priorBidTargetTick * tickSpacing));
        console2.log('priorBidTargetTick', priorBidTargetTick);
        console2.log('tickSpacing', tickSpacing);
        console2.log('auction.floorPrice()', auction.floorPrice() >> FixedPoint96.RESOLUTION);
        console2.log('priorBidMaxPrice', priorBidMaxPrice);
        address[] memory bidOwners = new address[](1);
        bidOwners[0] = address(this);
        bool successPriorBid = helper__setAuctionClearingPrice(priorBidMaxPrice, bidOwners, false);
        assertTrue(successPriorBid);
        assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, priorBidMaxPrice);

        // --- Submit the bid setting the target clearing price ---
        uint128 legalizedTargetClearingPrice = _legalizeBidMaxPrice(targetClearingPrice, false);
        console2.log('legalizedTargetClearingPrice', legalizedTargetClearingPrice);

        // Move the clearing price to the target price
        bool success = helper__setAuctionClearingPrice(legalizedTargetClearingPrice, bidOwners, false);

        // Not successful if clearing price is greater then target, since the price can only go up
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        if (clearingPrice < floorPrice) {
            clearingPrice = floorPrice;
        }
        console2.log('adjusted clearingPrice', clearingPrice);

        if (clearingPrice > legalizedTargetClearingPrice) {
            assertFalse(success);
            return;
        }
        assertTrue(success);
        assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, legalizedTargetClearingPrice);
    }

    function test_combinatorial_helpers_setAuctionClearingPrice_Q96(uint128 targetClearingPrice) public {
        // uint128 targetClearingPrice = 1e17;

        uint128 legalizedTargetClearingPrice = _legalizeBidMaxPrice(targetClearingPrice, true);

        // Move the clearing price to the target price
        address[] memory bidOwners = new address[](3);
        bidOwners[0] = address(this);
        bidOwners[0] = alice;
        bidOwners[0] = bob;
        bool success = helper__setAuctionClearingPrice(legalizedTargetClearingPrice, bidOwners, false);

        // Not successful if clearing price is greater then target, since the price can only go up
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        if (clearingPrice < floorPrice) {
            clearingPrice = floorPrice;
        }
        console2.log('adjusted clearingPrice', clearingPrice);

        if (clearingPrice > legalizedTargetClearingPrice) {
            assertFalse(success);
            return;
        }
        assertTrue(success);
        assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, legalizedTargetClearingPrice);
    }
}
