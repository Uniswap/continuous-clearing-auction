// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
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

        // Dynamically build the array of ticks to the length of the number of initialized ticks
        // done in assembly to prevent large memory expansion costs
        assembly {
            let dataStart := mload(0x40)
            let dataOffset := dataStart

            let idx := 0
            for {} lt(idx, MAX_BUFFER_SIZE) { idx := add(idx, 1) } {
                mstore(0x00, 0x534cb30d) // ContinuousClearingAuction.ticks(uint256)
                mstore(0x20, next)

                let success := staticcall(gas(), auction, 0x1c, 0x24, dataOffset, 0x40)
                if iszero(success) {
                    revert(0x00, 0x00)
                }

                let nextTick := mload(dataOffset)
                mstore(dataOffset, next)
                mstore(add(dataOffset, 0x40), 0)
                mstore(add(dataOffset, 0x60), 0)

                next := nextTick
                dataOffset := add(dataOffset, 0x80)

                if eq(nextTick, not(0)) {
                    idx := add(idx, 1)
                    break
                }
            }

            ticks := dataOffset
            mstore(ticks, idx)

            let pointerOffset := ticks
            for { let i := 0 } lt(i, idx) { i := add(i, 1) } {
                pointerOffset := add(pointerOffset, 0x20)
                mstore(pointerOffset, add(dataStart, mul(i, 0x80)))
            }
            mstore(0x40, add(pointerOffset, 0x20))
        }

        // Compute values over the initialized ticks
        uint256 runningDemand = sumCurrencyDemandAboveClearingQ96;
        for (uint256 i = 0; i < ticks.length; i++) {
            uint256 requiredCurrencyDemandQ96;
            if (remainingMps > 0) {
                requiredCurrencyDemandQ96 =
                    remainingSupplyQ96X7.fullMulDivUp(ticks[i].priceQ96, requiredDemandDenominator);
            }
            ticks[i].requiredCurrencyDemandQ96 = requiredCurrencyDemandQ96;
            ticks[i].currencyRequiredQ96 =
                requiredCurrencyDemandQ96.saturatingSub(runningDemand).fullMulDivUp(remainingMps, mps);
            runningDemand -= ticks[i].currencyDemandQ96;
        }
    }
}
