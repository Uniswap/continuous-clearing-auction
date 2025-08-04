// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct Tick {
    uint128 id;
    uint128 prev;
    uint128 next;
    uint256 price;
    uint256 sumCurrencyDemand; // Sum of demand in the `currency` (exactIn)
    uint256 sumTokenDemand; // Sum of demand in the `token` (exactOut)
}

library TickLib {
    function demand(Tick memory tick, uint256 tickSpacing) internal pure returns (uint256) {
        return demandAtPrice(tick.price, tickSpacing, tick.sumCurrencyDemand, tick.sumTokenDemand);
    }

    function demandAtPrice(uint256 price, uint256 tickSpacing, uint256 sumCurrencyDemand, uint256 sumTokenDemand)
        internal
        pure
        returns (uint256)
    {
        return (sumCurrencyDemand * tickSpacing / price) + sumTokenDemand;
    }
}
