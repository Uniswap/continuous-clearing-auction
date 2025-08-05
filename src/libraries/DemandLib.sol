// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Demand {
    uint256 currencyDemand;
    uint256 tokenDemand;
}

library DemandLib {
    function resolve(Demand memory _demand, uint256 price, uint256 tickSpacing) internal pure returns (uint256) {
        return price == 0 ? 0 : (_demand.currencyDemand * tickSpacing / price) + _demand.tokenDemand;
    }

    function resolveCurrencyDemand(Demand memory _demand, uint256 price, uint256 tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return price == 0 ? 0 : _demand.currencyDemand * tickSpacing / price;
    }

    function resolveTokenDemand(Demand memory _demand) internal pure returns (uint256) {
        return _demand.tokenDemand;
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

    function addCurrencyAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand + _amount, tokenDemand: _demand.tokenDemand});
    }

    function addTokenAmount(Demand memory _demand, uint256 _amount) internal pure returns (Demand memory) {
        return Demand({currencyDemand: _demand.currencyDemand, tokenDemand: _demand.tokenDemand + _amount});
    }
}
