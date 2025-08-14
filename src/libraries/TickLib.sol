// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Demand, DemandLib} from './DemandLib.sol';

struct Tick {
    uint128 id;
    uint128 prev;
    uint128 next;
    uint256 price;
    Demand demand;
}

library TickLib {
    using DemandLib for Demand;

    function resolveDemand(Tick memory tick, uint256 tickSpacing) internal pure returns (uint256) {
        return tick.demand.resolve(tickSpacing, tick.price);
    }
}
