// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './ValueX7X7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Struct containing currency demand and token demand
/// @dev All values are in ValueX7 format
struct Demand {
    ValueX7 currencyDemandX7;
    ValueX7 tokenDemandX7;
}

/// @title DemandLib
/// @notice Library for demand calculations and operations
library DemandLib {
    using DemandLib for ValueX7;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    /// @notice Resolve the demand at a given price, rounding up
    /// @dev "Resolving" means converting all demand into token terms, which requires dividing the currency demand by a price
    /// @param _demand The demand to resolve
    /// @param price The price to resolve the demand at
    /// @return The resolved demand as a ValueX7
    function resolveRoundingUp(Demand memory _demand, uint256 price) internal pure returns (ValueX7) {
        return _resolveCurrencyDemandRoundingUp(_demand.currencyDemandX7, price).add(_demand.tokenDemandX7);
    }

    function _resolveCurrencyDemandRoundingUp(ValueX7 amount, uint256 price) private pure returns (ValueX7) {
        return price == 0 ? ValueX7.wrap(0) : amount.wrapAndFullMulDivUp(FixedPoint96.Q96, price);
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

    function mulUint256(Demand memory _demand, uint256 value) internal pure returns (Demand memory) {
        return Demand({
            currencyDemandX7: _demand.currencyDemandX7.mulUint256(value),
            tokenDemandX7: _demand.tokenDemandX7.mulUint256(value)
        });
    }
}
