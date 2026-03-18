// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7} from './ValueX7Lib.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title DemandLib
/// @notice Library for demand calculations
library DemandLib {
    using Math for uint256;

    /// @notice Returns the demand required to move the auction to a given price
    /// @dev Accounts for supply rollover by comparing remaining supply to the expected schedule
    /// @dev Caller MUST validate that the auction is not over (cumulativeMps < MPS)
    /// @param _remainingSupplyQ96X7 The remaining supply in Q96 representation, scaled up by X7
    /// @param _priceQ96 The price to calculate demand at
    /// @param _remainingMps The number of mps remaining in the auction
    /// @return requiredDemandQ96 The demand required to move the auction to a given price, in Q96
    function requiredDemandAtPrice(ValueX7 _remainingSupplyQ96X7, uint256 _priceQ96, uint256 _remainingMps)
        internal
        pure
        returns (uint256 requiredDemandQ96)
    {
        // Unsold tokens from earlier blocks are implicitly rolled over to current and future blocks.
        // The required demand needed to clear the auction follows:
        //
        //     requiredDemand = TotalSupply * r * price
        //
        // where `r` measures how far the auction has deviated from the expected issuance schedule.
        // Intuitively, `r` scales the *remaining schedule* so that the full supply is still cleared
        // by the end of the auction.
        //
        // Examples:
        //   r == 1 → the auction is clearing exactly on schedule.
        //   r == 2 → half of the tokens that should have been sold so far remain unsold, so the
        //            remaining blocks must clear tokens at 2× the scheduled rate.
        //
        // From the schedule definition:
        //
        //     r = (TotalSupply - TotalCleared) / (TotalSupply * (MPS - cumulativeMps))
        //
        // Substituting `r` into the demand formula cancels `TotalSupply`:
        //
        //     requiredDemand = (TotalSupply - TotalCleared) * price / (MPS - cumulativeMps)
        //
        // We do not track `(TotalSupply - TotalCleared)` directly, but instead store
        // `(TotalSupply - TotalCleared) * Q96 * MPS` via `remainingSupplyQ96X7()`.
        //
        // Substituting this value yields:
        //
        //     requiredDemand = remainingSupplyQ96X7() * price
        //                      / (Q96 * (MPS - cumulativeMps))
        //
        // The `mps` factor is applied later when computing the per-block scheduled issuance.
        //
        requiredDemandQ96 = FixedPointMathLib.fullMulDivUp(
            ValueX7.unwrap(_remainingSupplyQ96X7), _priceQ96, FixedPoint96.Q96 * _remainingMps
        );
    }

    /// @notice Returns true if the demand is sufficient to clear the supply at the given price
    /// @dev This is a variant of the `DemandLib.requiredDemandAtPrice` function which
    ///      avoids intermediate division by using 512 bit multiplication to move terms to the LHS.
    /// @param _demandQ96 The available demand in Q96 representation
    /// @param _remainingSupplyQ96X7 The remaining supply in Q96 representation, scaled up by X7
    /// @param _priceQ96 The price to check if the supply can be cleared at
    /// @param _remainingMps The number of mps remaining in the auction
    /// @return true if the demand is sufficient to clear the supply at the given price, false otherwise
    function canClearSupplyAtPrice(
        uint256 _demandQ96,
        uint256 _remainingSupplyQ96X7,
        uint256 _priceQ96,
        uint256 _remainingMps
    ) internal pure returns (bool) {
        // Equivalent to: demandQ96 >= requiredDemandAtPrice()
        // Fully expanded:
        //     demandQ96 >= remainingSupplyQ96X7 * priceQ96 / (Q96 * remainingMps)
        //
        // Multiplying the LHS by Q96 to eliminate the division:
        //     demandQ96 * Q96 * remainingMps >= remainingSupplyQ96X7 * priceQ96
        //
        // Since demand is a Q96 term, we need to use 512 bit multiplication to avoid overflow of uint256.
        (uint256 highLhs, uint256 lowLhs) = Math.mul512(_demandQ96 * _remainingMps, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(_remainingSupplyQ96X7, _priceQ96);
        return highLhs > highRhs || (highLhs == highRhs && lowLhs >= lowRhs);
    }
}
