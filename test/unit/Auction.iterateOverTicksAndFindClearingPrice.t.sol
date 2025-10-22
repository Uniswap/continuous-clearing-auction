// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Place holder for BTT testing as that is not merged yet
import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';

import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {MockAuction} from '../utils/MockAuction.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct FuzzTick {
    uint8 tickNumber;
    uint128 demand;
}

contract AuctionIterateOverTicksAndFindClearingPriceTest is AuctionUnitTest {
    using FixedPointMathLib for *;

    function updateFuzzTicksExactlyAtAndAbove(FuzzTick[] memory _fuzzTicks, uint8 _tickNumber, uint256 _totalSupply)
        public
    {
        // Work out what the highest tick number is given the tick spacing and floor price
        uint256 highestTickNumber = (type(uint256).max - params.floorPrice) / params.tickSpacing;
        _tickNumber = uint8(_bound(_tickNumber, 0, highestTickNumber));

        uint256 tickPrice = params.floorPrice + uint256(_tickNumber) * uint256(params.tickSpacing);
        uint256 nextTickPrice = tickPrice + params.tickSpacing;

        // We need demand that makes the clearing price round up to nextTickPrice
        // The clearing price is calculated as: sumCurrencyDemandAboveClearingQ96_.fullMulDivUp(1, TOTAL_SUPPLY)
        // We want this to equal nextTickPrice, so we need demand = totalSupply * nextTickPrice
        // But we also need to ensure the iteration stops, which happens when:
        // 1. sumCurrencyDemandAboveClearingQ96_ < TOTAL_SUPPLY * nextActiveTickPrice_ AND
        // 2. clearingPrice != nextActiveTickPrice_
        // Since we want clearingPrice == nextTickPrice, we need to set up the ticks so that
        // nextActiveTickPrice_ > nextTickPrice, which means we need demand at a tick above nextTickPrice
        uint256 demandRequired = uint256(_totalSupply) * nextTickPrice;

        // Demand found above the tick should be greater than the demand required
        uint256 demandFoundAboveTick = 0;
        for (uint256 i = 0; i < _fuzzTicks.length; i++) {
            // Do not add demand to the floor price tick
            if (_fuzzTicks[i].tickNumber == 0) {
                continue;
            }

            if (demandFoundAboveTick >= demandRequired) {
                break;
            }
            if (_fuzzTicks[i].tickNumber > _tickNumber) {
                if (demandFoundAboveTick + _fuzzTicks[i].demand > demandRequired) {
                    _fuzzTicks[i].demand = uint128(demandRequired - demandFoundAboveTick);
                }
                demandFoundAboveTick += _fuzzTicks[i].demand;
            }

            // Add demand to the tick
            createOrAddToTickDemand(_fuzzTicks[i]);
        }

        // We need to ensure we have demand at the next tick (tickNumber + 1) to make clearing price = nextTickPrice
        // And we need demand at a tick above that to ensure iteration stops
        if (demandFoundAboveTick < demandRequired) {
            uint8 tickAboveNumberInspectingTick = _tickNumber + 1;

            uint256 demandDelta = demandRequired - demandFoundAboveTick;
            FuzzTick memory tickAbove =
                FuzzTick({tickNumber: tickAboveNumberInspectingTick, demand: uint128(demandDelta)});
            demandFoundAboveTick += demandDelta;

            createOrAddToTickDemand(tickAbove);
        }

        // We don't need extra demand at a higher tick since we want the clearing price to be exactly nextTickPrice

        assertEq(demandFoundAboveTick, demandRequired);
    }

    function createOrAddToTickDemand(FuzzTick memory _fuzzTick) public {
        uint256 tickPrice = params.floorPrice + uint256(_fuzzTick.tickNumber) * uint256(params.tickSpacing);

        if (_fuzzTick.tickNumber > 0) {
            mockAuction.uncheckedAddToSumDemandAboveClearing(uint256(_fuzzTick.demand));
        }

        mockAuction.uncheckedInitializeTickIfNeeded(params.floorPrice, tickPrice);
        mockAuction.uncheckedUpdateTickDemand(tickPrice, uint256(_fuzzTick.demand));
    }

    // Hack to prevent muliplying up too high
    // TODO: this implies a relationship between total supply and tick spacing
    modifier lowerTotalSupply(FuzzDeploymentParams memory _deploymentParams) {
        _deploymentParams.totalSupply = uint128(_bound(_deploymentParams.totalSupply, 1, uint128(type(uint96).max) - 1));
        _;
    }

    modifier tickSpacingIsFloorPrice(FuzzDeploymentParams memory _deploymentParams) {
        _deploymentParams.auctionParams.floorPrice = _deploymentParams.auctionParams.tickSpacing;
        _;
    }

    /// forge.config.isolate = true
    // function test_WhenThereIsEnoughDemandExactlyAtAndAboveTheTick(
    //     FuzzDeploymentParams memory _deploymentParams,
    //     FuzzTick[] memory _fuzzTicks,
    //     uint8 _tickNumber
    // ) external
    //     lowerTotalSupply(_deploymentParams)
    //     tickSpacingIsFloorPrice(_deploymentParams)
    //     setUpMockAuctionFuzz(_deploymentParams)
    // {
    //     // it should set clearing price to a tick boundary
    //     // it should find clearing price rounded up to be the minimum price
    //     // it should find clearing price rounded down to be the minimum price
    //     // it should set sumDemandAboveClearing to be sum of ticks above clearing price

    //     // Sum demand above clearing should be enough to purchase all tokens at given ticks

    //     // How to structure this test
    //     // - Update the sum demand above clearing
    //     // - Update the ticks with the correct demand
    //     // - Allow for some kind of jitter for the ticks that will be used

    //     assertEq(params.tickSpacing, params.floorPrice);
    //     uint256 totalSupply = mockAuction.totalSupply();

    //     _tickNumber = uint8(bound(_tickNumber, 1, 252));
    //     updateFuzzTicksExactlyAtAndAbove(_fuzzTicks, _tickNumber, totalSupply);

    //     // Set up the checkpoint corrrectly
    //     Checkpoint memory checkpoint = Checkpoint({
    //         clearingPrice: params.floorPrice,
    //         currencyRaisedAtClearingPriceQ96_X7: ValueX7.wrap(0),
    //         cumulativeMpsPerPrice: 0,
    //         cumulativeMps: 0,
    //         prev: 0,
    //         next: type(uint64).max
    //     });

    //     // Set the next active tick price to the first tick above floor price
    //     uint256 firstTickAboveFloor = params.floorPrice + params.tickSpacing;
    //     mockAuction.uncheckedSetNextActiveTickPrice(firstTickAboveFloor);

    //     uint256 clearingPrice = mockAuction.iterateOverTicksAndFindClearingPrice(checkpoint);
    //     uint256 expectedClearingPrice = params.floorPrice + uint256(_tickNumber + 1) * uint256(params.tickSpacing);

    //     console.log("tick spacing", params.tickSpacing);
    //     console.log("floor price", params.floorPrice);
    //     console.log("tick number", _tickNumber);
    //     console.log("clearing price", clearingPrice);
    //     console.log("price at tick number", params.floorPrice + uint256(_tickNumber) * uint256(params.tickSpacing));
    //     console.log("expected clearing price", expectedClearingPrice);

    //     assertEq(clearingPrice, expectedClearingPrice);
    // }

    function test_WhenThereIsEnoughDemandExactlyAtAndAboveTheTick() external {
        // it should set clearing price to a tick boundary
        // it should find clearing price rounded up to be the minimum price
        // it should find clearing price rounded down to be the minimum price
        // it should set sumDemandAboveClearing to be sum of ticks above clearing price

        setUpMockAuction();

        uint256 totalSupply = mockAuction.totalSupply();

        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;

        uint256 sumDemandAboveClearing = totalSupply * nextTickPrice;
        mockAuction.uncheckedAddToSumDemandAboveClearing(sumDemandAboveClearing);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, nextTickPrice);
        mockAuction.uncheckedUpdateTickDemand(nextTickPrice, sumDemandAboveClearing);

        // TODO: could it be that the next active tick price was 0 in the fuzz test?
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

        // In this case, the clearing price rounded down should be the clearing price
        uint256 clearingPriceRoundedDown = sumDemandAboveClearing.fullMulDiv(1, totalSupply);
        assertEq(clearingPriceRoundedDown, clearingPrice, 'clearing price rounded down should be the clearing price');

        // In this case, the clearing price rounded up should be the next tick price
        uint256 clearingPriceRoundedUp = sumDemandAboveClearing.fullMulDivUp(1, totalSupply);
        assertEq(clearingPriceRoundedUp, clearingPrice, 'clearing price rounded up should be the clearing price');

        // Sum demand above clearing should be 0 as all demand is at the correct tick
        assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), 0, 'sum demand above clearing should be 0');
    }

    function test_WhenThereIsEnoughDemandAtTheTickAndTicksAboveButNotEnoughDemandAtTicksAboveToFindAClearingPriceInbetween()
        external
    {
        // it should set clearing price to a tick boundary
        // it should set sumDemandAboveClearing to be sum of ticks above clearing price

        setUpMockAuction();

        uint256 totalSupply = mockAuction.totalSupply();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;
        uint256 secondTickPrice = nextTickPrice + tickSpacing;

        // Add 3/4 demand to the next tick and 1/4 demand to the second tick
        uint256 demandAtNextTick = totalSupply * nextTickPrice * 3 / 4;
        uint256 sumDemandAboveClearing = demandAtNextTick;
        mockAuction.uncheckedAddToSumDemandAboveClearing(sumDemandAboveClearing);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, nextTickPrice);
        mockAuction.uncheckedUpdateTickDemand(nextTickPrice, sumDemandAboveClearing);

        uint256 demandAtSecondTick = totalSupply * secondTickPrice * 1 / 4;
        sumDemandAboveClearing += demandAtSecondTick;
        mockAuction.uncheckedAddToSumDemandAboveClearing(demandAtSecondTick);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, secondTickPrice);
        mockAuction.uncheckedUpdateTickDemand(secondTickPrice, demandAtSecondTick);

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

        // In this case, the clearing price rounded down should be BELOW the next tick price
        uint256 sumDemandAboveClearingFromAuction = mockAuction.sumCurrencyDemandAboveClearingQ96();
        uint256 clearingPriceRoundedDown = sumDemandAboveClearingFromAuction.fullMulDiv(1, totalSupply);
        assertLt(
            clearingPriceRoundedDown, nextTickPrice, 'clearing price rounded down should be below the next tick price'
        );

        // In this case, the clearing price rounded up should be below the next tick price
        uint256 clearingPriceRoundedUp = sumDemandAboveClearingFromAuction.fullMulDivUp(1, totalSupply);
        assertLt(clearingPriceRoundedUp, nextTickPrice, 'clearing price rounded up should be below the next tick price');

        // Sum demand above clearing should be the demand at the second tick price
        assertEq(sumDemandAboveClearingFromAuction, demandAtSecondTick);
    }

    function test_WhenThereIsEnoughDemandAtTheTicksAboveToFindAClearingPriceBetweenTickBoundaries() external {
        // it should find clearing price between tick boundaries
        // it should find clearing price rounded up to be above tick lower < tick upper
        // it should find clearing price rounded down to be above tick lower < tick upper
        // it should set sumDemandAboveClearing to be sum of ticks above clearing price

        setUpMockAuction();

        uint256 totalSupply = mockAuction.totalSupply();
        uint256 tickSpacing = mockAuction.tickSpacing();
        uint256 floorPrice = mockAuction.floorPrice();
        uint256 nextTickPrice = floorPrice + tickSpacing;
        uint256 secondTickPrice = nextTickPrice + tickSpacing;

        // Add 3/4 demand to the next tick and 90/100 demand to the second tick
        uint256 demandAtNextTick = totalSupply * nextTickPrice * 3 / 4;
        uint256 sumDemandAboveClearing = demandAtNextTick;
        mockAuction.uncheckedAddToSumDemandAboveClearing(sumDemandAboveClearing);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, nextTickPrice);
        mockAuction.uncheckedUpdateTickDemand(nextTickPrice, sumDemandAboveClearing);

        uint256 demandAtSecondTick = totalSupply * secondTickPrice * 99 / 100;
        sumDemandAboveClearing += demandAtSecondTick;
        mockAuction.uncheckedAddToSumDemandAboveClearing(demandAtSecondTick);
        mockAuction.uncheckedInitializeTickIfNeeded(floorPrice, secondTickPrice);
        mockAuction.uncheckedUpdateTickDemand(secondTickPrice, demandAtSecondTick);

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

        // The clearing price should be found between the next tick price and the second tick price
        assertGt(clearingPrice, nextTickPrice);
        assertLt(clearingPrice, secondTickPrice);

        // In this case, the clearing price rounded down should be inbetween the next tick price and the second tick price
        uint256 clearingPriceRoundedDown = demandAtSecondTick.fullMulDiv(1, totalSupply);
        assertGt(clearingPriceRoundedDown, nextTickPrice);
        assertLt(clearingPriceRoundedDown, secondTickPrice);

        // In this case, the clearing price rounded up should be inbetween the next tick price and the second tick price
        uint256 clearingPriceRoundedUp = demandAtSecondTick.fullMulDivUp(1, totalSupply);
        assertGt(clearingPriceRoundedUp, nextTickPrice);
        assertLt(clearingPriceRoundedUp, secondTickPrice);

        // assert approx rounded up and down
        assertApproxEqAbs(clearingPriceRoundedDown, clearingPriceRoundedUp, 1);

        // Sum demand above clearing should be the demand at the second tick price
        assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), demandAtSecondTick);
    }

    function test_WhenThereIsEnoughDemandToFallBelowTheNextTickButRoundsUpToTheNextTick() external {
        // it should find clearing price at next tick boundary
        // it should find clearing price rounded down falls below tick boundary
        // it should find demand at next tick < currency raised at clearing price
        // it should set sumDemandAboveClearing to be sum of ticks above clearing price

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

        // In this case, the clearing price rounded down should be below the next tick price
        uint256 clearingPriceRoundedDown = sumDemandAboveClearing.fullMulDiv(1, totalSupply);
        assertLt(clearingPriceRoundedDown, nextTickPrice);

        // In this case, the clearing price rounded up should be the next tick price
        uint256 clearingPriceRoundedUp = sumDemandAboveClearing.fullMulDivUp(1, totalSupply);
        assertEq(clearingPriceRoundedUp, nextTickPrice);

        // assert approx rounded up and down
        assertApproxEqAbs(clearingPriceRoundedDown, clearingPriceRoundedUp, 1);

        // Sum demand above clearing should be 0
        assertEq(mockAuction.sumCurrencyDemandAboveClearingQ96(), 0);
    }
}
