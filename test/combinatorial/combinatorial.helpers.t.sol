// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';
import {FuzzBid} from '../utils/FuzzStructs.sol';
import {PostBidScenario} from './combinatorialEnums.sol';
import {PreBidScenario} from './combinatorialEnums.sol';

import {Test} from 'forge-std/Test.sol';
import {console2} from 'forge-std/console2.sol';

contract CombinatorialHelpersTest is AuctionBaseTest {
    function helper__preBidScenario(PreBidScenario scenario) public pure {
        if (scenario == PreBidScenario.NoBidsBeforeUser) {
            return;
        } else if (scenario == PreBidScenario.BidsBeforeUser) {
            return;
        } else if (scenario == PreBidScenario.ClearingPriceBelowMaxPrice) {
            return;
        } else {
            revert('Invalid pre bid scenario');
        }
    }

    function helper__postBidScenario(PostBidScenario scenario, uint256 userMaxPrice) public {
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        if (userMaxPrice % tickSpacing != 0) {
            revert('postBidScenario: userMaxPrice not compliant with tickSpacing');
        }

        if (scenario == PostBidScenario.NoBidsAfterUser) {
            return;
        } else if (scenario == PostBidScenario.UserAboveClearing) {
            if (userMaxPrice <= clearingPrice + tickSpacing) {
                // User's bid is at or right above the clearing price
                return;
            } else {
                // User's bid is more then one tick above clearing: Move clearing right below the user's bid
                helper__setAuctionClearingPrice(userMaxPrice - tickSpacing, new address[](1));
                return;
            }
        } else if (scenario == PostBidScenario.UserAtClearing) {
            if (userMaxPrice <= clearingPrice) {
                // User's bid is at or right above the clearing price
                return;
            } else {
                // User's bid is more then one tick above clearing: Move clearing right below the user's bid
                helper__setAuctionClearingPrice(userMaxPrice, new address[](1));
                return;
            }
        } else if (scenario == PostBidScenario.UserOutbidLater) {
            if (userMaxPrice < clearingPrice) {
                // User's bid is already below the clearing price
                return;
            } else {
                // User's bid is above or equal to the clearing price: Move clearing above the user's bid after one block
                vm.roll(block.number + 1); // Outbid in the next block
                helper__setAuctionClearingPrice(userMaxPrice + tickSpacing, new address[](1));
                return;
            }
        } else if (scenario == PostBidScenario.UserOutbidImmediately) {
            if (userMaxPrice < clearingPrice) {
                // User's bid is already below the clearing price
                return;
            } else {
                // User's bid is above or equal to the clearing price: Move clearing above the user's bid immediately
                helper__setAuctionClearingPrice(userMaxPrice + tickSpacing, new address[](1));
                return;
            }
        } else {
            revert('Invalid post bid scenario');
        }
    }

    function helper__setAuctionClearingPrice(uint256 targetClearingPrice, address[] memory bidOwners)
        public
        returns (bool success)
    {
        Checkpoint memory checkpoint = auction.checkpoint();
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        if (clearingPrice > targetClearingPrice) {
            return false; // Clearing price is already greater than target clearing price
        } else if (clearingPrice == targetClearingPrice) {
            return true;
        } else {
            uint256 totalSupply = auction.totalSupply();
            // uint256 bidAmountToMoveToTargetClearingPrice = totalSupply * targetClearingPrice;
            uint256 bidAmountToMoveToTargetClearingPrice =
                (totalSupply - ((totalSupply * checkpoint.cumulativeMps) / ConstantsLib.MPS)) * targetClearingPrice;
            if (bidAmountToMoveToTargetClearingPrice > uint256(type(uint128).max)) {
                revert('Bid amount to move to target clearing price is too large');
            }

            vm.deal(address(this), bidAmountToMoveToTargetClearingPrice);
            console2.log('bidAmountToMoveToTargetClearingPrice', bidAmountToMoveToTargetClearingPrice);
            uint256 allBidAmounts = 0;
            uint256 i = 0;
            while (bidOwners.length > 0) {
                uint256 bidAmount = bidAmountToMoveToTargetClearingPrice / bidOwners.length;
                allBidAmounts += bidAmount;
                if (i == bidOwners.length - 1) {
                    // last bid, add the remaining bid amount
                    bidAmount += bidAmountToMoveToTargetClearingPrice - allBidAmounts;
                }
                if (bidAmount == 0) {
                    break;
                }
                address bidOwner = bidOwners[i];
                try auction.submitBid{value: bidAmount}(
                    targetClearingPrice << FixedPoint96.RESOLUTION, uint128(bidAmount), bidOwner, bytes('')
                ) returns (uint256) {
                    vm.roll(block.number + 1);
                    auction.checkpoint();
                } catch (bytes memory) {
                    return false;
                }

                i++;
                if (i >= bidOwners.length) {
                    break;
                }
            }
            return true;
        }
    }

    function _legalizeBidMaxPrice(uint256 maxPrice) internal view returns (uint64 targetClearingPrice) {
        uint256 auctionTickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        console2.log('auctionTickSpacing', auctionTickSpacing);

        uint256 targetClearingPriceTemp = helper__roundPriceUpToTickSpacing(maxPrice, auctionTickSpacing);
        targetClearingPrice = uint64(bound(targetClearingPriceTemp, 1, 1e17));

        console2.log('rounded targetClearingPrice', targetClearingPrice);

        return targetClearingPrice;
    }

    function setUp() public {
        setUpAuction();
    }

    function test_combinatorial_helpers_postBidScenario(FuzzBid memory bid, uint8 scenarioSelection) public {
        console2.log('TEST STARTING');
        auction.checkpoint();
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;
        console2.log('tickSpacing:', tickSpacing);
        console2.log('floorPrice:', floorPrice);
        console2.log('clearingPrice original:', clearingPrice);
        // -- Tests with fixed values --
        bid.bidAmount = 1 ether;
        bid.tickNumber = 20;
        scenarioSelection = 4;

        console2.log('bid.tickNumber:', bid.tickNumber);

        PostBidScenario scenario = PostBidScenario(scenarioSelection % uint256(PostBidScenario.__length));

        uint256 maxPrice =
            helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(bid.tickNumber) >> FixedPoint96.RESOLUTION;
        (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(0, bid, alice);
        console2.log('bidPlaced:', bidPlaced);
        if (bidPlaced) {
            assertEq(auction.bids(bidId).maxPrice >> FixedPoint96.RESOLUTION, maxPrice);
        }

        console2.log('Scenario:', uint256(scenario));
        console2.log('User max price:', maxPrice);
        console2.log('clearingPrice before Scenario:', auction.clearingPrice() >> FixedPoint96.RESOLUTION);
        helper__postBidScenario(scenario, maxPrice);
        console2.log('clearingPrice after Scenario:', auction.clearingPrice() >> FixedPoint96.RESOLUTION);
        if (scenario == PostBidScenario.NoBidsAfterUser) {
            assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, clearingPrice);
        } else if (scenario == PostBidScenario.UserAboveClearing) {
            assertTrue(auction.clearingPrice() >> FixedPoint96.RESOLUTION > clearingPrice);
            assertTrue(auction.clearingPrice() >> FixedPoint96.RESOLUTION < maxPrice);
        } else if (scenario == PostBidScenario.UserAtClearing) {
            assertTrue(auction.clearingPrice() >> FixedPoint96.RESOLUTION == maxPrice);
        } else if (scenario == PostBidScenario.UserOutbidLater) {
            assertTrue(auction.bids(bidId).startBlock < auction.bids(bidId + 1).startBlock);
            assertTrue(auction.clearingPrice() >> FixedPoint96.RESOLUTION > maxPrice);
        } else if (scenario == PostBidScenario.UserOutbidImmediately) {
            assertTrue(auction.bids(bidId).startBlock == auction.bids(bidId + 1).startBlock);
            assertTrue(auction.clearingPrice() >> FixedPoint96.RESOLUTION > maxPrice);
        } else {
            revert('Invalid post bid scenario');
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

        uint128 legalizedTargetClearingPrice = _legalizeBidMaxPrice(targetClearingPrice);

        // Move the clearing price to the target price
        address[] memory bidOwners = new address[](3);
        bidOwners[0] = address(this);
        bidOwners[0] = alice;
        bidOwners[0] = bob;
        bool success = helper__setAuctionClearingPrice(legalizedTargetClearingPrice, bidOwners);

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
        bool successPriorBid = helper__setAuctionClearingPrice(priorBidMaxPrice, bidOwners);
        assertTrue(successPriorBid);
        assertEq(auction.clearingPrice() >> FixedPoint96.RESOLUTION, priorBidMaxPrice);

        // --- Submit the bid setting the target clearing price ---
        uint128 legalizedTargetClearingPrice = _legalizeBidMaxPrice(targetClearingPrice);
        console2.log('legalizedTargetClearingPrice', legalizedTargetClearingPrice);

        // Move the clearing price to the target price
        bool success = helper__setAuctionClearingPrice(legalizedTargetClearingPrice, bidOwners);

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
