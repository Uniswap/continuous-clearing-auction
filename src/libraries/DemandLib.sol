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
    /// @notice Given demand above and at a price, calculate the currency raised by all bids at the price
    /// @dev Gets the minimum of the complement based on demand above the price or the max possible
    ///      currency raised from demand at the price.
    /// @dev Caller MUST validate that the auction is not over (_remainingMps > 0)
    /// @param _remainingSupplyQ96X7 The remaining supply in Q96 representation, scaled up by X7
    /// @param _demandAtPriceQ96 The demand at the price
    /// @param _demandAbovePriceQ96 The demand above the price
    /// @param _priceQ96 The price to calculate the currency raised at
    /// @param _deltaMps The number of mps to sell
    /// @param _remainingMps The number of mps remaining in the auction
    /// @return currencyRaisedAtPriceQ96X7 The currency raised at the price
    function currencyRaisedAtPrice(
        ValueX7 _remainingSupplyQ96X7,
        uint256 _demandAtPriceQ96,
        uint256 _demandAbovePriceQ96,
        uint256 _priceQ96,
        uint256 _deltaMps,
        uint256 _remainingMps
    ) internal pure returns (ValueX7 currencyRaisedAtPriceQ96X7) {
        // Natural definitions
        uint256 currencyRaisedFromDemandAbovePriceQ96X7 = _demandAbovePriceQ96 * _deltaMps;
        uint256 maxCurrencyRaisedFromDemandAtPriceQ96X7 = _demandAtPriceQ96 * _deltaMps;

        // Clearing prices are always rounded up to prevent overallocating tokens to those who would have been outbid
        // Thus the total implied currencyRaised at the clearing price can be an overestimate if the price was rounded up.
        // This is a variant of src/libraries/DemandLib.sol:requiredDemandAtPrice but with `mps` in the numerator to minimize rounding errors.
        uint256 totalCurrencyRaisedQ96X7 = FixedPointMathLib.fullMulDivUp(
            ValueX7.unwrap(_remainingSupplyQ96X7), _priceQ96 * _deltaMps, FixedPoint96.Q96 * _remainingMps
        );

        // Find the currency raised at price via complement (A = total - above)
        uint256 complementToDemandAbovePriceQ96X7 =
            FixedPointMathLib.saturatingSub(totalCurrencyRaisedQ96X7, currencyRaisedFromDemandAbovePriceQ96X7);

        // Cap at the maximum possible currency raised from demand at price
        currencyRaisedAtPriceQ96X7 = ValueX7.wrap(
            FixedPointMathLib.min(complementToDemandAbovePriceQ96X7, maxCurrencyRaisedFromDemandAtPriceQ96X7)
        );
    }

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
        // where `r` is the ratio between the actual remaining supply and the expected remaining supply.
        // The auction will never allocate tokens faster than the preset schedule, so `r` can only be >= 1.
        //
        // From the schedule definition:
        //
        //     r = (TotalSupply - TotalCleared) * MPS / (TotalSupply * (MPS - cumulativeMps))
        //
        // Substituting `r` into the demand formula cancels `TotalSupply`:
        //
        //     requiredDemand = (TotalSupply - TotalCleared) * price * MPS / (MPS - cumulativeMps)
        //
        // We do not track `(TotalSupply - TotalCleared)` directly, but instead store
        // `(TotalSupply - TotalCleared) * Q96 * MPS` via `remainingSupplyQ96X7()`.
        //
        // Multiplying by Q96/Q96 and substituting this value yields:
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

    /// @notice Returns the price ceiling implied by the given demand, assuming demand is continuous
    /// @dev The actual clearing price may be lower due to demand dropping off at tick boundaries.
    ///      Wrapper around `PriceLib.toPriceRoundingUp()` that moves the division of remainingMps
    ///      to the LHS as multiplication to avoid intermediate division.
    /// @param _demandQ96 The demand in Q96 representation
    /// @param _remainingSupplyQ96X7 The remaining supply in Q96 representation, scaled up by X7
    /// @param _remainingMps The number of mps remaining in the auction
    /// @return The price ceiling, in Q96 representation
    function toPriceCeiling(uint256 _demandQ96, uint256 _remainingSupplyQ96X7, uint256 _remainingMps)
        internal
        pure
        returns (uint256)
    {
        return PriceLib.toPriceRoundingUp(_demandQ96 * _remainingMps, _remainingSupplyQ96X7);
    }
}
