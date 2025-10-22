// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Place holder for BTT testing as that is not merged yet
import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {MockAuction} from '../utils/MockAuction.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {console} from 'forge-std/console.sol';

contract AuctionSellTokensAtClearingPriceTest is AuctionUnitTest {
    using FixedPointMathLib for *;

    function test_WhenThereIsEnoughDemandExactlyAtAndAboveTheTick(uint24 _deltaMps) external {
        // it should not sell more tokens than there is available supply at the current tick - parital fill
        // it should increase currency raise by amount of tokens there are to sell at the current tick
        // it should set the cumulativeMpsPerPrice with the rounded up clearing price
        // it should update cumulative mps by deltaMps

        _deltaMps = uint24(bound(_deltaMps, 1, ConstantsLib.MPS));

        setUpMockAuction();

        uint256 totalSupply = mockAuction.totalSupply();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;

        uint256 sumDemandAboveClearing = totalSupply * nextTickPrice;
        mockAuction.uncheckedAddToSumDemandAboveClearing(sumDemandAboveClearing);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, nextTickPrice);
        mockAuction.uncheckedUpdateTickDemand(nextTickPrice, sumDemandAboveClearing);

        mockAuction.uncheckedSetNextActiveTickPrice(nextTickPrice);

        Checkpoint memory checkpoint = Checkpoint({
            clearingPrice: floorPrice,
            currencyRaisedAtClearingPriceQ96_X7: ValueX7.wrap(0),
            cumulativeMpsPerPrice: 0,
            cumulativeMps: 0,
            prev: 0,
            next: type(uint64).max
        });

        // Note: this is the clearing price rounded up
        uint256 clearingPrice = mockAuction.iterateOverTicksAndFindClearingPrice(checkpoint);
        checkpoint.clearingPrice = clearingPrice;

        // TODO: fuzz this value
        Checkpoint memory newCheckpoint = mockAuction.sellTokensAtClearingPrice(checkpoint, _deltaMps);

        // All demand above the clearing price should be removed
        assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), 0);

        // Currency raised ex
        // In this example it will be exactly the same
        uint256 expectedCurrencyRaised = sumDemandAboveClearing * _deltaMps;
        uint256 expectedCurrencyRaisedFromSumDemandAboveClearing = 0 * _deltaMps;
        uint256 expectedCurrencyAtClearingPrice = totalSupply * clearingPrice * _deltaMps;

        assertEq(
            expectedCurrencyRaised, expectedCurrencyAtClearingPrice - expectedCurrencyRaisedFromSumDemandAboveClearing
        );
        assertEq(mockAuction.currencyRaisedQ96_X7(), ValueX7.wrap(expectedCurrencyAtClearingPrice));

        // Value of demand at the tick should be equal to the value of currency raised when multiplying total supply by clearing price
        uint256 currencyRaisedAtTick = mockAuction.ticks(clearingPrice).currencyDemandQ96 * _deltaMps;
        assertEq(currencyRaisedAtTick, expectedCurrencyAtClearingPrice);

        // Currency raised at clearing price should be equal to the sum of demand above clearing and the demand at the tick
        assertEq(newCheckpoint.currencyRaisedAtClearingPriceQ96_X7, ValueX7.wrap(expectedCurrencyAtClearingPrice));

        uint256 expectedCumulativeMpsPerPrice =
            (_deltaMps * (FixedPoint96.Q96 << FixedPoint96.RESOLUTION)) / clearingPrice;
        assertEq(newCheckpoint.cumulativeMpsPerPrice, expectedCumulativeMpsPerPrice);
        assertEq(newCheckpoint.cumulativeMps, _deltaMps);
    }

    function test_WhenThereIsEnoughDemandAtTheTickAndTicksAboveButNotEnoughDemandAtTicksAboveToFindAClearingPriceBetween()
        external {
        // it should sell tokens at the clearing price - there should be no demand at the current clearing price
        // it should set the cumulativeMpsPerPrice with the new floor at tick spacing
        // it should update cumulative mps by deltaMps
    }

    function test_WhenThereIsEnoughDemandAtTheTicksAboveToFindAClearingPriceBetweenTickBoundaries() external {
        // it should update cumulative mps by deltaMps
        // it should update the cumulativeMpsPerPrice with the rounded up clearing price
        // it should set currencyRaisedAtClearingPrice to 0
        // it should increase currencyRaised_X7 by sumCurrencyDemandAboveCleaingQ64 * deltaMps
        // it should set the cumulativeMpsPerPrice with the rounded up clearing price
        // it should update cumulative mps by deltaMps
    }

    function test_WhenThereIsEnoughDemandToFallBelowTheNextTickButRoundsUpToTheNextTick() external {
        // it should not sell more tokens than there is demand at the rounded up tick
        // it should set currencyRaisedAtClearing price to be the sum with demand at the rounded up tick
        // it should set the cumulativeMpsPerPrice with the rounded up clearing price
        // it should update cumulative mps by deltaMps

        setUpMockAuction();

        uint256 totalSupply = mockAuction.totalSupply();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;

        // Add enough demand to the next tick to round up to the next tick price
        uint256 demandAtNextTick = (totalSupply * nextTickPrice) - 1;
        uint256 sumDemandAboveClearing = demandAtNextTick;

        mockAuction.uncheckedAddToSumDemandAboveClearing(sumDemandAboveClearing);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, nextTickPrice);
        mockAuction.uncheckedUpdateTickDemand(nextTickPrice, sumDemandAboveClearing);

        mockAuction.uncheckedSetNextActiveTickPrice(nextTickPrice);

        Checkpoint memory checkpoint = Checkpoint({
            clearingPrice: floorPrice,
            currencyRaisedAtClearingPriceQ96_X7: ValueX7.wrap(0),
            cumulativeMpsPerPrice: 0,
            cumulativeMps: 0,
            prev: 0,
            next: type(uint64).max
        });
        uint256 clearingPrice = mockAuction.iterateOverTicksAndFindClearingPrice(checkpoint);

        assertEq(clearingPrice, nextTickPrice);

        // In this case, the clearing price rounded up should be the next tick price
        {
            // In this case, the clearing price rounded down should be below the next tick price
            uint256 clearingPriceRoundedDown = sumDemandAboveClearing.fullMulDiv(1, totalSupply);
            assertLt(clearingPriceRoundedDown, nextTickPrice);

            uint256 clearingPriceRoundedUp = sumDemandAboveClearing.fullMulDivUp(1, totalSupply);
            assertEq(clearingPriceRoundedUp, nextTickPrice);

            // assert approx rounded up and down
            assertApproxEqAbs(clearingPriceRoundedDown, clearingPriceRoundedUp, 1);

            // Sum demand above clearing should be 0
            assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), 0);
        }

        uint24 _deltaMps = 100;
        checkpoint.clearingPrice = clearingPrice;
        Checkpoint memory newCheckpoint = mockAuction.sellTokensAtClearingPrice(checkpoint, _deltaMps);

        // Currency raised ex
        // In this example it will be exactly the same
        uint256 expectedCurrencyRaised = sumDemandAboveClearing * _deltaMps;
        uint256 expectedCurrencyRaisedFromSumDemandAboveClearing = 0 * _deltaMps;
        uint256 expectedCurrencyAtClearingPrice = totalSupply * clearingPrice * _deltaMps;

        // The currency raised at the tick should be STRICTLY less than the expected currency due to expected using a rounded up clearing price
        uint256 demandAtTick = mockAuction.ticks(clearingPrice).currencyDemandQ96;

        uint256 currencyRaisedAtTick = demandAtTick * _deltaMps;
        assertLt(currencyRaisedAtTick, expectedCurrencyAtClearingPrice);

        // These values should be off by exactly 1 * deltaMps
        // NOTE: this is where the larger wei discrepancies are coming from - the ronding error is being scaled up by mps
        assertApproxEqAbs(expectedCurrencyAtClearingPrice, currencyRaisedAtTick, 1 * _deltaMps);
        assertGt(expectedCurrencyAtClearingPrice, currencyRaisedAtTick);
        assertEq(expectedCurrencyRaised, currencyRaisedAtTick - expectedCurrencyRaisedFromSumDemandAboveClearing);

        // FALING
        // Note here: we are calculating currency raised as if we have filled the whole thing successfully,
        // however we actually have not - this is using the rounded up clearing price to determine - and
        // thus is probably calculting that we have earned more than we actually have
        assertEq(mockAuction.currencyRaisedQ96_X7(), ValueX7.wrap(currencyRaisedAtTick));

        // Currency raised at clearing price should be equal to the sum of demand above clearing and the demand at the tick
        assertEq(newCheckpoint.currencyRaisedAtClearingPriceQ96_X7, ValueX7.wrap(currencyRaisedAtTick));

        uint256 expectedCumulativeMpsPerPrice =
            (_deltaMps * (FixedPoint96.Q96 << FixedPoint96.RESOLUTION)) / clearingPrice;
        assertEq(newCheckpoint.cumulativeMpsPerPrice, expectedCumulativeMpsPerPrice);
        assertEq(newCheckpoint.cumulativeMps, _deltaMps);
    }
}
