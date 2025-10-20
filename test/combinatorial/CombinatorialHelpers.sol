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

import {Test} from 'forge-std/Test.sol';
import {console2} from 'forge-std/console2.sol';

contract CombinatorialHelpers is AuctionBaseTest {
    function helper__preBidScenario(PreBidScenario scenario, uint256 userMaxPrice) public {
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = auction.floorPrice() >> FixedPoint96.RESOLUTION;

        if (userMaxPrice % tickSpacing != 0) {
            revert('preBidScenario: userMaxPrice not compliant with tickSpacing');
        }

        if (scenario == PreBidScenario.NoBidsBeforeUser) {
            // No action needed - auction starts with no bids
            return;
        } else if (scenario == PreBidScenario.BidsBeforeUser) {
            // Place bids that raise clearing price, but keep it below userMaxPrice
            // Move clearing to midpoint between floor and userMaxPrice
            uint256 targetClearingPrice;
            if (userMaxPrice > floorPrice + tickSpacing * 2) {
                // Place clearing at least 2 ticks below userMaxPrice
                targetClearingPrice = userMaxPrice - (2 * tickSpacing);
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1));
            } else {
                // userMaxPrice is too close to floor, just keep at floor
                return;
            }
        } else if (scenario == PreBidScenario.ClearingPriceBelowMaxPrice) {
            // Raise clearing price to exactly one tick below userMaxPrice
            if (userMaxPrice > floorPrice + tickSpacing) {
                uint256 targetClearingPrice = userMaxPrice - tickSpacing;
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1));
                return;
            } else {
                // userMaxPrice is already only one tick above floor, just keep at floor
                return;
            }
        } else if (scenario == PreBidScenario.BidsAtClearingPrice) {
            // First, move clearing price to one tick below userMaxPrice
            if (userMaxPrice > floorPrice + tickSpacing) {
                uint256 targetClearingPrice = userMaxPrice - tickSpacing;
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1));
            }

            // Then place a small bid at exactly userMaxPrice (not large enough to move clearing)
            uint256 smallBidAmount = 0.01 ether; // Small bid amount
            vm.deal(address(this), smallBidAmount);
            auction.submitBid{value: smallBidAmount}(
                userMaxPrice << FixedPoint96.RESOLUTION, uint128(smallBidAmount), address(this), bytes('')
            );
            vm.roll(block.number + 1);
            auction.checkpoint();
            return;
        } else {
            revert('Invalid pre bid scenario');
        }
    }

    function helper__postBidScenario(PostBidScenario scenario, uint256 userMaxPrice) public {
        uint256 tickSpacing = auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        if (userMaxPrice % tickSpacing != 0) {
            revert('postBidScenario: userMaxPrice not compliant with tickSpacing');
        }

        uint256 snap = vm.snapshot();
        vm.roll(block.number + 1);
        auction.checkpoint();
        uint256 clearingPrice = auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        vm.revertToState(snap);

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
            console2.log('should trigger 1');
            if (userMaxPrice <= clearingPrice) {
                // User's bid is at or right above the clearing price
                return;
            } else {
                console2.log('should trigger 2');
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
}
