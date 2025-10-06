// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {BidLib} from '../../src/libraries/BidLib.sol';
import {CheckpointLib} from '../../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
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
    using BidLib for Bid;
    using FixedPointMathLib for uint256;
    using CheckpointLib for Checkpoint;

    modifier givenValidMps(uint24 remainingMps) {
        vm.assume(remainingMps > 0 && remainingMps <= ConstantsLib.MPS);
        _;
    }

    modifier givenValidCheckpoint(Checkpoint memory _checkpoint) {
        vm.assume(_checkpoint.cumulativeMps > 0 && _checkpoint.cumulativeMps <= ConstantsLib.MPS);
        _;
    }

    // Less fuzz runs because this is a pretty intensive test
    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_iterateOverTicks(
        FuzzDeploymentParams memory _deploymentParams,
        FuzzBid[] memory _bids,
        Checkpoint memory _checkpoint
    ) public setUpMockAuctionFuzz(_deploymentParams) setUpBidsFuzz(_bids) givenValidCheckpoint(_checkpoint) {
        // Assume there are still tokens to sell in the auction
        vm.assume(_checkpoint.remainingMpsInAuction() > 0);
        _checkpoint.totalCurrencyRaisedX7X7 = ValueX7X7.wrap(
            _bound(
                ValueX7X7.unwrap(_checkpoint.totalCurrencyRaisedX7X7),
                0,
                ValueX7X7.unwrap(mockAuction.getTotalCurrencyRaisedAtFloorX7X7()) - 1
            )
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

            mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, maxPrice);
            // TODO(ez): start cumulative mps can be fuzzed to not be 0
            mockAuction.uncheckedUpdateTickDemand(maxPrice, helper__toDemand(_bids[i], 0));
            mockAuction.uncheckedAddToSumDemandAboveClearing(helper__toDemand(_bids[i], 0));
            mockAuction.uncheckedCreateBid(_bids[i].bidAmount, alice, maxPrice, 0);
        }
        // Start checkpoint at the floor price
        _checkpoint.clearingPrice = mockAuction.floorPrice();
        // Set the next active tick price to the lowest tick price so we can iterate over them
        mockAuction.uncheckedSetNextActiveTickPrice(lowestTickPrice);
        // Ensure fullMulDiv result doesn't overflow: (type(uint256).max * floorPrice) / lowestTickPrice <= type(uint256).max
        vm.assume(mockAuction.floorPrice() <= lowestTickPrice);
        vm.assume(
            ValueX7X7.unwrap(mockAuction.getTotalCurrencyRaisedAtFloorX7X7().sub(_checkpoint.totalCurrencyRaisedX7X7))
                < type(uint256).max.fullMulDiv(mockAuction.floorPrice(), lowestTickPrice)
        );

        uint256 clearingPrice = mockAuction.iterateOverTicksAndFindClearingPrice(_checkpoint);
        // Assert that the clearing price is greater than or equal to the floor price
        assertGe(clearingPrice, mockAuction.floorPrice());
        // Assert that the clearing price is less than or equal to the highest tick price
        // This must be true because we can't find a price higher than the max price of all the bids
        assertLe(clearingPrice, highestTickPrice);

        // Assert that the sumDemandAboveClearing is less than the currency required to move to the next active tick
        if (mockAuction.nextActiveTickPrice() != type(uint256).max) {
            assertLt(
                ValueX7X7.unwrap(mockAuction.sumCurrencyDemandAboveClearingX7().upcast()),
                ValueX7X7.unwrap(
                    mockAuction.getTotalCurrencyRaisedAtFloorX7X7().sub(_checkpoint.totalCurrencyRaisedX7X7)
                        .wrapAndFullMulDivUp(mockAuction.nextActiveTickPrice(), mockAuction.floorPrice())
                ),
                'sumCurrencyDemandAboveClearingX7 is greater than or equal to currency required to move to the next active tick'
            );
        }
    }
}
