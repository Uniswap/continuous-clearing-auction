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

    function resolve(Demand memory _demand, uint256 price) internal pure returns (ValueX7) {
        return _demand.currencyDemand.resolveCurrencyDemand(price).add(_demand.tokenDemand);
    }

    function resolveCurrencyDemand(ValueX7 amount, uint256 price) internal pure returns (ValueX7) {
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

    /// @notice Apply mps to demand
    /// @dev Requires both currencyDemand and tokenDemand to be > MPS to avoid loss of precision
    function applyMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.applyMps(mps),
            tokenDemand: _demand.tokenDemand.applyMps(mps)
        });
    }
}
