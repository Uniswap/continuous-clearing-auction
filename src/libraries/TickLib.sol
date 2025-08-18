// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Demand, DemandLib} from './DemandLib.sol';

struct Tick {
    uint128 next;
    uint128 prev;
    Demand demand;
}
