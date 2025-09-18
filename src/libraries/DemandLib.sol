// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';

import {MPSLib, ValueX7} from './MPSLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Demand {
    ValueX7 currencyDemand;
    ValueX7 tokenDemand;
}

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
        return _resolveCurrencyDemand(_demand.currencyDemand, price).add(_demand.tokenDemand);
    }

    /// @notice Resolve the currency demand at a given price
    function _resolveCurrencyDemand(ValueX7 amount, uint256 price) private pure returns (ValueX7) {
        return price == 0 ? ValueX7.wrap(0) : ValueX7.wrap(ValueX7.unwrap(amount).fullMulDiv(FixedPoint96.Q96, price));
    }

    function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.add(_other.currencyDemand),
            tokenDemand: _demand.tokenDemand.add(_other.tokenDemand)
        });
    }

    function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.sub(_other.currencyDemand),
            tokenDemand: _demand.tokenDemand.sub(_other.tokenDemand)
        });
    }

    /// @notice Apply mps to a Demand struct
    /// @dev Shorthand for calling `scaleByMps` on both currencyDemand and tokenDemand
    function scaleByMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.scaleByMps(mps),
            tokenDemand: _demand.tokenDemand.scaleByMps(mps)
        });
    }
}
