// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {Tick} from '../interfaces/ITickStorage.sol';
import {ConstantsLib} from '../libraries/ConstantsLib.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';
import {ValueX7} from '../libraries/ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Tick data with additional computed values
/// @dev Use the ratio between `sumCurrencyDemandAboveClearingQ96` in the auction
///      and `requiredCurrencyDemandQ96` to calculate the progress towards the tick
///      Use `currencyRequiredQ96` to calculate the additional currency needed to move the clearing price to the tick.
struct TickWithData {
    uint256 priceQ96; // the price of the tick
    uint256 currencyDemandQ96; // the current demand at the tick
    uint256 requiredCurrencyDemandQ96; // the required demand to move the clearing price to the tick
    uint256 currencyRequiredQ96; // the additional currency required to move the clearing price to the tick
}

/// @title TickDataLens
/// @notice Contract for reading data from initialized ticks of an auction
contract TickDataLens {
    using FixedPointMathLib for uint256;

    /// @notice The maximum number of initialized ticks which can be returned
    uint256 public constant MAX_BUFFER_SIZE = 1000;

    /// @notice Function to be called from offchain to get the data of all initialized ticks above a given price
    /// @dev A maximum of `MAX_BUFFER_SIZE` ticks above the current clearing price will be returned
    ///      Returned values may be stale if the auction has not been recently checkpointed
    function getInitializedTickData(IContinuousClearingAuction auction)
        public
        view
        returns (TickWithData[] memory ticks)
    {
        uint24 mps = ConstantsLib.MPS;
        uint24 remainingMps = mps - auction.latestCheckpoint().cumulativeMps;
        uint256 remainingSupplyQ96X7 = ValueX7.unwrap(auction.remainingSupplyQ96X7());
        uint256 requiredDemandDenominator = FixedPoint96.Q96 * remainingMps;
        // Retrieve the sumCurrencyDemandAboveClearingQ96 from storage
        uint256 sumCurrencyDemandAboveClearingQ96 = auction.sumCurrencyDemandAboveClearingQ96();
        // Get the next active tick price
        uint256 next = auction.nextActiveTickPrice();

        if (next == type(uint256).max) {
            revert();
        }

        uint256 count;
        uint256 tickPrice = next;
        while (count < MAX_BUFFER_SIZE) {
            Tick memory tick = auction.ticks(tickPrice);
            count++;
            tickPrice = tick.next;
            if (tickPrice == type(uint256).max) {
                break;
            }
        }

        ticks = new TickWithData[](count);
        tickPrice = next;
        uint256 runningDemand = sumCurrencyDemandAboveClearingQ96;
        for (uint256 i = 0; i < count; i++) {
            Tick memory tick = auction.ticks(tickPrice);
            uint256 requiredCurrencyDemandQ96;
            if (remainingMps > 0) {
                requiredCurrencyDemandQ96 = remainingSupplyQ96X7.fullMulDivUp(tickPrice, requiredDemandDenominator);
            }
            ticks[i] = TickWithData({
                priceQ96: tickPrice,
                currencyDemandQ96: tick.currencyDemandQ96,
                requiredCurrencyDemandQ96: requiredCurrencyDemandQ96,
                currencyRequiredQ96: requiredCurrencyDemandQ96.saturatingSub(runningDemand)
                    .fullMulDivUp(remainingMps, mps)
            });
            runningDemand -= tick.currencyDemandQ96;
            tickPrice = tick.next;
        }
    }
}
