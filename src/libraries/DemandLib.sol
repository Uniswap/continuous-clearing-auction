// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';

import {FixedPoint96} from './FixedPoint96.sol';

import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Demand {
    uint256 currencyDemand;
    uint256 tokenDemand;
}

library DemandLib {
    using DemandLib for uint256;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    function resolve(Demand memory _demand, uint256 price, bool currencyIsToken0) internal pure returns (uint256) {
        return
            price == 0 ? 0 : _demand.currencyDemand.resolveCurrencyDemand(price, currencyIsToken0) + _demand.tokenDemand;
    }

    /// @notice Resolve the currency demand at a price based on currencyIsToken0
    /// @return the demand in terms of `token`
    function resolveCurrencyDemand(uint256 amount, uint256 price, bool currencyIsToken0)
        internal
        pure
        returns (uint256)
    {
        if (price == 0 || amount == 0) return 0;
        if (currencyIsToken0) {
            return amount.fullMulDiv(price, FixedPoint96.Q96);
        } else {
            return amount.fullMulDiv(FixedPoint96.Q96, price);
        }
    }

    function resolveTokenDemand(uint256 amount) internal pure returns (uint256) {
        return amount;
    }

    function sub(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand - _other.currencyDemand,
            tokenDemand: _demand.tokenDemand - _other.tokenDemand
        });
    }

    function add(Demand memory _demand, Demand memory _other) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand + _other.currencyDemand,
            tokenDemand: _demand.tokenDemand + _other.tokenDemand
        });
    }

    function applyMps(Demand memory _demand, uint24 mps) internal pure returns (Demand memory) {
        return Demand({
            currencyDemand: _demand.currencyDemand.applyMps(mps),
            tokenDemand: _demand.tokenDemand.applyMps(mps)
        });
    }

    function addCurrencyAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand + _amount, tokenDemand: _demand.tokenDemand});
    }

    function addTokenAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand, tokenDemand: _demand.tokenDemand + _amount});
    }
}
