// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Tick} from './TickLib.sol';

library DemandLib {
    function demand(Tick memory tick, uint256 tickSpacing) internal pure returns (uint256) {
        return demand(tick.price, tickSpacing, tick.sumCurrencyDemand, tick.sumTokenDemand);
    }

    function demand(uint256 price, uint256 tickSpacing, uint256 sumCurrencyDemand, uint256 sumTokenDemand)
        internal
        pure
        returns (uint256)
    {
        return (sumCurrencyDemand * tickSpacing / price) + sumTokenDemand;
    }
}
