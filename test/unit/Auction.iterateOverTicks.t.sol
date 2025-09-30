// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';

import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {CheckpointLib} from '../../src/libraries/CheckpointLib.sol';
import {Demand, DemandLib} from '../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {MPSLib} from '../../src/libraries/MPSLib.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../../src/libraries/ValueX7X7Lib.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {FuzzBid} from '../utils/FuzzStructs.sol';
import {MockAuction} from '../utils/MockAuction.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionIterateOverTicksTest is AuctionUnitTest {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using DemandLib for Demand;
    using BidLib for Bid;
    using FixedPointMathLib for uint256;
    using CheckpointLib for Checkpoint;

    modifier givenValidMps(uint24 remainingMps) {
        vm.assume(remainingMps > 0 && remainingMps <= MPSLib.MPS);
        _;
    }

    modifier givenValidCheckpoint(Checkpoint memory _checkpoint) {
        vm.assume(_checkpoint.cumulativeMps > 0 && _checkpoint.cumulativeMps <= MPSLib.MPS);
        _checkpoint.totalClearedX7X7 = ValueX7X7.wrap(
            _bound(
                ValueX7X7.unwrap(_checkpoint.totalClearedX7X7),
                0,
                ValueX7X7.unwrap(mockAuction.totalSupply().scaleUpToX7().scaleUpToX7X7())
            )
        );
        _;
    }

    function test_iterateOverTicks(
        FuzzDeploymentParams memory _deploymentParams,
        FuzzBid[] memory _bids,
        Checkpoint memory _checkpoint,
        Demand memory _sumDemandAboveClearing
    ) public setUpMockAuctionFuzz(_deploymentParams) setUpBidsFuzz(_bids) givenValidCheckpoint(_checkpoint) {
        // Assume there are still tokens to sell in the auction
        vm.assume(_checkpoint.remainingMpsInAuction() > 0);
        vm.assume(
            ValueX7X7.unwrap(mockAuction.totalSupply().scaleUpToX7().scaleUpToX7X7().sub(_checkpoint.totalClearedX7X7))
                > 0
        );
        // Insert the bids into the auction without creating checkpoints or going through the normal logic
        // This involves initializing ticks, updating tick demand, updating sum demand above clearing, and inserting the bids into storage
        uint256 lowestTickPrice;
        uint256 highestTickPrice;
        for (uint256 i = 0; i < _bids.length; i++) {
            uint256 maxPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(_bids[i].tickNumber);
            // Update the lowest and highest tick prices as we iterate
            lowestTickPrice = lowestTickPrice == 0 ? maxPrice : lowestTickPrice < maxPrice ? lowestTickPrice : maxPrice;
            highestTickPrice =
                highestTickPrice == 0 ? maxPrice : highestTickPrice > maxPrice ? highestTickPrice : maxPrice;

            bool exactIn = maxPrice % 2 == 0;
            mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, maxPrice);
            // TODO(ez): start cumulative mps can be fuzzed to not be 0
            mockAuction.uncheckedUpdateTickDemand(maxPrice, helper__toDemand(_bids[i], exactIn, 0));
            mockAuction.uncheckedAddToSumDemandAboveClearing(helper__toDemand(_bids[i], exactIn, 0));
            mockAuction.uncheckedCreateBid(exactIn, _bids[i].bidAmount, alice, maxPrice, 0);
        }
        // Start checkpoint at the floor price
        _checkpoint.clearingPrice = mockAuction.floorPrice();
        // Set the next active tick price to the lowest tick price so we can iterate over them
        mockAuction.uncheckedSetNextActiveTickPrice(lowestTickPrice);

        uint256 clearingPrice = mockAuction.iterateOverTicksAndFindClearingPrice(_checkpoint);

        // Assert that the sumDemandAboveClearing is less than or equal to the remaining supply in the auction
        // If it was, that would mean that the price discovered by the iteration was too low, and we should have found a higher price
        assertLe(
            ValueX7X7.unwrap(mockAuction.sumDemandAboveClearing().resolveRoundingUp(clearingPrice).upcast()),
            ValueX7X7.unwrap(mockAuction.totalSupply().scaleUpToX7().scaleUpToX7X7().sub(_checkpoint.totalClearedX7X7)),
            'sumDemandAboveClearing is greater than remaining supply'
        );
    }
}
