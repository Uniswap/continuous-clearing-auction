// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Demand, DemandLib} from './DemandLib.sol';

struct Tick {
    uint256 next;
    uint256 prev;
    Demand demand;
}

library TickLib {}
