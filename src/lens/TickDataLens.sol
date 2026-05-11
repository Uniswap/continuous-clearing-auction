// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickStorage} from '../TickStorage.sol';
import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {Tick} from '../interfaces/ITickStorage.sol';
import {ConstantsLib} from '../libraries/ConstantsLib.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';
import {ValueX7} from '../libraries/ValueX7Lib.sol';
import {AuctionState} from './AuctionStateLens.sol';
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
    using FixedPointMathLib for *;

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

        assembly {
            let m := mload(0x40)
            let offset := m

            let idx := 0
            for {} lt(idx, MAX_BUFFER_SIZE) { idx := add(idx, 1) } {
                // Store the next tick price as the first argument to the ticks function call
                mstore(0x00, 0x534cb30d) // ContinuousClearingAuction.ticks(uint256)
                mstore(0x20, next)
                // Call the ticks function - write the return value directly at the offset
                let success := staticcall(gas(), auction, 0x1c, 0x24, offset, 0x40)
                // If the call fails, revert
                if iszero(success) {
                    revert(0x00, 0x00)
                }
                // Load the next tick price from the return value
                let nextTick := mload(offset)
                // Overwrite the next tick price with the current tick price
                mstore(offset, next)

                // Calculate and store the requiredCurrencyDemandQ96 using the auction's rollover-aware formula:
                // fullMulDivUp(remainingSupplyQ96X7, priceQ96, Q96 * remainingMps)
                let requiredCurrencyDemandQ96 := 0
                if remainingMps {
                    requiredCurrencyDemandQ96 := fullMulDivUp(remainingSupplyQ96X7, next, requiredDemandDenominator)
                }
                mstore(add(offset, 0x40), requiredCurrencyDemandQ96)

                // Calculate and store the currencyRequiredQ96:
                // currencyRequiredQ96 = saturatingSub(required, sum).mulDivUp(remainingMps, MPS)
                let currencyRequiredQ96 :=
                    mulDivUp(
                        saturatingSub(requiredCurrencyDemandQ96, sumCurrencyDemandAboveClearingQ96),
                        remainingMps,
                        mps
                    )
                mstore(add(offset, 0x60), currencyRequiredQ96)

                // update sumCurrencyDemandAboveClearingQ96 by subtracting the currencyDemandQ96 at the current tick
                let currencyDemandQ96 := mload(add(offset, 0x20))
                sumCurrencyDemandAboveClearingQ96 := sub(sumCurrencyDemandAboveClearingQ96, currencyDemandQ96)

                // update next to the next tick price returned by the ticks function
                next := nextTick

                // update offset to the next tick data
                offset := add(offset, 0x80)

                // If the next tick price is the maximum uint256 value or we have reached the maximum buffer size, break the loop
                if eq(nextTick, not(0)) {
                    // Update idx to the number of ticks returned
                    idx := add(idx, 1)
                    break
                }
            }

            // Assign the return value to the right memory location
            ticks := offset
            // Assign the length of the TickWithData array to the first word of the return value
            mstore(ticks, idx)
            // Assign the absolute pointers after the length to the return value
            for { let i := 0 } lt(i, idx) { i := add(i, 1) } {
                offset := add(offset, 0x20)
                let absolutePointer := add(m, mul(i, 0x80))
                mstore(offset, absolutePointer)
            }
            // Update the free memory pointer to the end of the data
            mstore(0x40, add(offset, 0x20))

            // ----- Inline functions -----
            // ------------------------------------------------------------

            /// @dev Equivalent to FixedPointMathLib.saturatingSub: returns max(0, x - y).
            function saturatingSub(x, y) -> z {
                z := mul(gt(x, y), sub(x, y))
            }

            /// @dev Equivalent to FixedPointMathLib.fullMulDivUp: returns ceil(x * y / d).
            ///      Safe to use a plain `mul` instead of 512-bit math because `y` is
            ///      `remainingMps` (a uint24, max 1e7 ≈ 2^23), so x * y cannot overflow
            ///      uint256 for any realistic currency demand value.
            function mulDivUp(x, y, d) -> result {
                result := div(mul(x, y), d)
                if mulmod(x, y, d) {
                    result := add(result, 1)
                }
            }

            /// @dev Equivalent to FixedPointMathLib.fullMulDivUp: returns ceil(x * y / d).
            function fullMulDivUp(x, y, d) -> result {
                let denominator := d
                result := mul(x, y)
                for {} 1 {} {
                    if iszero(mul(or(iszero(x), eq(div(result, x), y)), d)) {
                        let mm := mulmod(x, y, not(0))
                        let p1 := sub(mm, add(result, lt(mm, result)))
                        let r := mulmod(x, y, d)
                        let t := and(d, sub(0, d))
                        if iszero(gt(d, p1)) {
                            mstore(0x00, 0xae47f702) // FullMulDivFailed()
                            revert(0x1c, 0x04)
                        }
                        d := div(d, t)
                        let inv := xor(2, mul(3, d))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        result := mul(
                            or(mul(sub(p1, gt(r, result)), add(div(sub(0, t), t), 1)), div(sub(result, r), t)),
                            mul(sub(2, mul(d, inv)), inv)
                        )
                        break
                    }
                    result := div(result, d)
                    break
                }
                if mulmod(x, y, denominator) {
                    result := add(result, 1)
                    if iszero(result) {
                        mstore(0x00, 0xae47f702) // FullMulDivFailed()
                        revert(0x1c, 0x04)
                    }
                }
            }

            // ------------------------------------------------------------
        }
    }
}
