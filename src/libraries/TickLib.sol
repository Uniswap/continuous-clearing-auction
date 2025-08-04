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
