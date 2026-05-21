// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from '../libraries/ConstantsLib.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';
import {ValueX7} from '../libraries/ValueX7Lib.sol';

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
        // Get the next active tick price
        uint256 next = auction.nextActiveTickPrice();

        if (next == type(uint256).max) {
            return new TickWithData[](0);
        }

        uint24 mps = ConstantsLib.MPS;
        uint24 remainingMps = mps - auction.latestCheckpoint().cumulativeMps;
        uint256 remainingSupplyQ96X7 = ValueX7.unwrap(auction.remainingSupplyQ96X7());
        uint256 requiredDemandDenominator = FixedPoint96.Q96 * remainingMps;
        // Seed the running demand from the auction's accumulator; it decays per tick below
        uint256 runningDemand = auction.sumCurrencyDemandAboveClearingQ96();

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
                    // Bubble up the inner revert reason so off-chain callers see the auction's error
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }

                let nextTick := mload(dataOffset)
                mstore(dataOffset, next)

                // requiredCurrencyDemandQ96 = remainingMps > 0
                //     ? ceil(remainingSupplyQ96X7 * next / (Q96 * remainingMps)) (full 512-bit)
                //     : 0
                // Guarded explicitly so the d == 0 case never reaches fullMulDivUp.
                let requiredCurrencyDemandQ96 := 0
                if gt(remainingMps, 0) {
                    requiredCurrencyDemandQ96 := fullMulDivUp(remainingSupplyQ96X7, next, requiredDemandDenominator)
                }
                mstore(add(dataOffset, 0x40), requiredCurrencyDemandQ96)

                // currencyRequiredQ96 = ceil(saturatingSub(required, runningDemand) * remainingMps / mps)
                mstore(
                    add(dataOffset, 0x60),
                    fullMulDivUp(saturatingSub(requiredCurrencyDemandQ96, runningDemand), remainingMps, mps)
                )

                next := nextTick
                // Defensive: clamp to zero rather than wrapping if the auction's sum is
                // ever inconsistent with per-tick demands (invariant should hold, but
                // silent wrap would corrupt every subsequent tick's currencyRequiredQ96).
                runningDemand := saturatingSub(runningDemand, /* currencyDemandQ96 */ mload(add(dataOffset, 0x20)))

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

            // ----- Inline functions -----
            // ------------------------------------------------------------

            /// @dev Equivalent to FixedPointMathLib.saturatingSub: returns max(0, x - y).
            function saturatingSub(x, y) -> z {
                z := mul(gt(x, y), sub(x, y))
            }

            /// @dev Equivalent to FixedPointMathLib.fullMulDivUp: returns ceil(x * y / d)
            ///      computed through a 512-bit intermediate. Mirrors Solady's
            ///      implementation; reverts via `FullMulDivFailed()` if the result
            ///      cannot fit in a uint256 (which also catches `d == 0` whenever
            ///      `x * y` overflows uint256).
            function fullMulDivUp(x, y, d) -> z {
                z := mul(x, y)
                for {} 1 {} {
                    if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                        let mm := mulmod(x, y, not(0))
                        let p1 := sub(mm, add(z, lt(mm, z)))
                        let r := mulmod(x, y, d)
                        let t := and(d, sub(0, d))
                        if iszero(gt(d, p1)) {
                            mstore(0x00, 0xae47f702) // `FullMulDivFailed()`
                            revert(0x1c, 0x04)
                        }
                        d := div(d, t)
                        let inv := xor(2, mul(3, d))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        inv := mul(inv, sub(2, mul(d, inv)))
                        z := mul(
                            or(mul(sub(p1, gt(r, z)), add(div(sub(0, t), t), 1)), div(sub(z, r), t)),
                            mul(sub(2, mul(d, inv)), inv)
                        )
                        break
                    }
                    z := div(z, d)
                    break
                }
                if mulmod(x, y, d) {
                    z := add(z, 1)
                    if iszero(z) {
                        mstore(0x00, 0xae47f702) // `FullMulDivFailed()`
                        revert(0x1c, 0x04)
                    }
                }
            }

            // ------------------------------------------------------------
        }
    }
}
