// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {MPSLib, ValueX7} from './MPSLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Struct containing currency demand and token demand
/// @dev All values are in ValueX7 format
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}

/// @title DemandLib
library DemandLib {
    using DemandLib for ValueX7;
    using MPSLib for *;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    /// @notice Resolve the demand at a given price
    /// @dev "Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price
    /// @param _demand The demand to resolve
    /// @param price The price to resolve the demand at
    /// @return The resolved demand as a ValueX7
    function resolve(Demand memory _demand, uint256 price) internal pure returns (ValueX7) {
        return _resolveCurrencyDemand(_demand.currencyDemandX7, price).add(_demand.tokenDemandX7);
    }

    /// @notice Resolve the currency demand at a given price
    function _resolveCurrencyDemand(ValueX7 amount, uint256 price) private pure returns (ValueX7) {
        return price == 0 ? ValueX7.wrap(0) : amount.fullMulDiv(ValueX7.wrap(FixedPoint96.Q96), ValueX7.wrap(price));
    }

    function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemandX7: _demand.currencyDemandX7.add(_other.currencyDemandX7),
            tokenDemandX7: _demand.tokenDemandX7.add(_other.tokenDemandX7)
        });
    }

    function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemandX7: _demand.currencyDemandX7.sub(_other.currencyDemandX7),
            tokenDemandX7: _demand.tokenDemandX7.sub(_other.tokenDemandX7)
        });
    }

    /// @notice Apply mps to a Demand struct
    /// @dev Shorthand for calling `scaleByMps` on both currencyDemandX7 and tokenDemandX7
    function scaleByMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory) {
        return Demand({
            currencyDemandX7: _demand.currencyDemandX7.scaleByMps(mps),
            tokenDemandX7: _demand.tokenDemandX7.scaleByMps(mps)
        });
    }
}
