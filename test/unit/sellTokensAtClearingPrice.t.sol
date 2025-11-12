// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Place holder for BTT testing as that is not merged yet
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {MockContinuousClearingAuction} from '../utils/MockAuction.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {console} from 'forge-std/console.sol';

contract AuctionSellTokensAtClearingPriceTest is AuctionUnitTest {
    using FixedPointMathLib for *;
    using ValueX7Lib for *;

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

        {
            // Currency raised ex
            // In this example it will be exactly the same
            uint256 expectedCurrencyRaised = sumDemandAboveClearing * _deltaMps;
            uint256 expectedCurrencyRaisedFromSumDemandAboveClearing = 0 * _deltaMps;
            uint256 expectedCurrencyAtClearingPrice = totalSupply * clearingPrice * _deltaMps;

            assertEq(
                expectedCurrencyRaised,
                expectedCurrencyAtClearingPrice - expectedCurrencyRaisedFromSumDemandAboveClearing
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

        // Assert that total cleared does not exceed the total supply sold
        assertLe(mockAuction.totalCleared(), (totalSupply * _deltaMps) / ConstantsLib.MPS);
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

    /// forge-config: default.fuzz.runs = 888
    function test_WhenThereIsEnoughDemandToFallBelowTheNextTickButRoundsUpToTheNextTick(FuzzDeploymentParams memory _deploymentParams)
        external
        setUpMockAuctionFuzz(_deploymentParams)
    {
        // it should not sell more tokens than there is demand at the rounded up tick
        // it should set currencyRaisedAtClearing price to be the sum with demand at the rounded up tick
        // it should set the cumulativeMpsPerPrice with the rounded up clearing price
        // it should update cumulative mps by deltaMps
        uint256 totalSupply = mockAuction.totalSupply();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;

        vm.assume(totalSupply < type(uint256).max / nextTickPrice);
        // Add enough demand to the next tick to round up to the next tick price
        uint256 demandAtNextTick = (totalSupply * nextTickPrice) - 1;
        uint256 sumDemandAboveClearing = demandAtNextTick;

        vm.assume(sumDemandAboveClearing < ConstantsLib.X7_UPPER_BOUND);

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

        // Require that the clearing price rounds up to the next tick price
        vm.assume(clearingPrice == nextTickPrice);

        // In this case, the clearing price rounded up should be the next tick price
        {
            // In this case, the clearing price rounded down should be below the next tick price
            uint256 clearingPriceRoundedDown = sumDemandAboveClearing.fullMulDiv(1, totalSupply);
            assertLt(clearingPriceRoundedDown, nextTickPrice);

            uint256 clearingPriceRoundedUp = sumDemandAboveClearing.divUp(totalSupply);
            assertEq(clearingPriceRoundedUp, nextTickPrice);

            // assert approx rounded up and down
            assertApproxEqAbs(clearingPriceRoundedDown, clearingPriceRoundedUp, 1);

            // Sum demand above clearing should be 0
            assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), 0);
        }

        {
            uint24 _deltaMps = 10_000;
            checkpoint.clearingPrice = clearingPrice;
            checkpoint = mockAuction.sellTokensAtClearingPrice(checkpoint, _deltaMps);

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

            // This line will fail if we use the rounded up clearing price to determine the currency raised
            assertEq(mockAuction.currencyRaisedQ96_X7(), ValueX7.wrap(currencyRaisedAtTick));

            // Currency raised at clearing price should be equal to the sum of demand above clearing and the demand at the tick
            assertEq(checkpoint.currencyRaisedAtClearingPriceQ96_X7, ValueX7.wrap(currencyRaisedAtTick));

            uint256 expectedCumulativeMpsPerPrice =
                (_deltaMps * (FixedPoint96.Q96 << FixedPoint96.RESOLUTION)) / clearingPrice;
            assertEq(checkpoint.cumulativeMpsPerPrice, expectedCumulativeMpsPerPrice);
            assertEq(checkpoint.cumulativeMps, _deltaMps);
        }

        // Assert that total cleared is less than or equal to the supply sold in the block
        assertLe(mockAuction.totalCleared(), (totalSupply * 10_000) / ConstantsLib.MPS);

        // Assume no change in the auction's demand, and fast forward to end of the auction
        {
            // Maximize the number of checkpoints to maximize the rounding error
            // we have already sold 1000 mps
            uint24 remainingMps = ConstantsLib.MPS - checkpoint.cumulativeMps;
            for (uint24 i = 0; i < remainingMps; i += 10_000) {
                checkpoint = mockAuction.sellTokensAtClearingPrice(checkpoint, 10_000);
            }
            assertEq(checkpoint.cumulativeMps, ConstantsLib.MPS);

            // From the previous setup in the test, we know that the clearing price == bid max price
            // Calculate the partial tokens filled
            ValueX7 currencySpentQ96_X7 = ValueX7.wrap(
                ValueX7.unwrap(demandAtNextTick.scaleUpToX7())
                    .fullMulDivUp(
                        ValueX7.unwrap(checkpoint.currencyRaisedAtClearingPriceQ96_X7),
                        // The bid was entered in the beginning of the auction so bid.remainingMpsInAuction == ConstantsLib.MPS
                        ValueX7.unwrap(demandAtNextTick.scaleUpToX7())
                    )
            );
            // The currency spent ValueX7 is then scaled down to a uint256
            uint256 currencySpentQ96 = currencySpentQ96_X7.scaleDownToUint256();
            // The tokens filled uses the currencySpent ValueX7 value and scales down to a uint256
            uint256 tokensFilled = currencySpentQ96_X7.divUint256(clearingPrice).scaleDownToUint256();

            // If the totalCleared is less than the tokens filled then the auction would be insolvent if
            // the bid exited and the unsold tokens were swept
            assertGe(mockAuction.totalCleared(), tokensFilled, 'total cleared not less than tokens filled');
        }
    }
}
