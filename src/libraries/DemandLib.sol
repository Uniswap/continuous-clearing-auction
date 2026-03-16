// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {PriceLib} from './PriceLib.sol';
import {ValueX7} from './ValueX7Lib.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title DemandLib
/// @notice Library for demand calculations
library DemandLib {
    using Math for uint256;
    using PriceLib for uint256;

    /// @notice Returns the demand required to move the auction to a given price
    /// @dev Accounts for supply rollover by comparing remaining supply to the expected schedule
    /// @dev Caller MUST validate that the auction is not over (cumulativeMps < MPS)
    /// @param _supplyQ96X7 The remaining supply in Q96 representation, scaled up by X7
    /// @param _priceQ96 The price to calculate demand at
    /// @param _cumulativeMps The number of mps sold in the auction so far
    /// @return requiredDemandQ96 The demand required to move the auction to a given price, in Q96
    function requiredDemandAtPrice(ValueX7 _supplyQ96X7, uint256 _priceQ96, uint256 _cumulativeMps)
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
            ValueX7.unwrap(_supplyQ96X7), _priceQ96, FixedPoint96.Q96 * (ConstantsLib.MPS - _cumulativeMps)
        );
    }

    /// @notice Returns true if the demand value is greater than or equal to
    function gte(uint256 _demandQ96, uint256 _supplyQ96X7, uint256 _priceQ96) internal pure returns (bool) {
        (uint256 highLhs, uint256 lowLhs) = Math.mul512(_demandQ96, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(_supplyQ96X7, _priceQ96);
        return highLhs > highRhs || (highLhs == highRhs && lowLhs >= lowRhs);
    }
}
