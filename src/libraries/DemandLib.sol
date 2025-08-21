// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStepLib} from './AuctionStepLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Demand {
    uint256 currencyDemand;
    uint256 tokenDemand;
}

library DemandLib {
    using DemandLib for uint256;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    function resolve(Demand memory _demand, uint256 price) internal pure returns (uint256) {
        return price == 0 ? 0 : _demand.currencyDemand.resolveCurrencyDemand(price) + _demand.tokenDemand;
    }

    function resolveCurrencyDemand(uint256 amount, uint256 price) internal pure returns (uint256) {
        return price == 0 ? 0 : amount / price;
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

    function applyMpsDenominator(Demand memory _demand, uint24 mps, uint24 mpsDenominator)
        internal
        pure
        returns (Demand memory)
    {
        return Demand({
            currencyDemand: _demand.currencyDemand.applyMpsDenominator(mps, mpsDenominator),
            tokenDemand: _demand.tokenDemand.applyMpsDenominator(mps, mpsDenominator)
        });
    }

    function addCurrencyAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand + _amount, tokenDemand: _demand.tokenDemand});
    }

    function addTokenAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand, tokenDemand: _demand.tokenDemand + _amount});
    }
}
