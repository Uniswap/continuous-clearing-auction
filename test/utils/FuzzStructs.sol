// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionParameters} from '../../src/ContinuousClearingAuction.sol';

/// @dev Parameters for fuzzing the auction
struct FuzzDeploymentParams {
    uint128 totalSupply;
    AuctionParameters auctionParams;
    uint8 numberOfSteps;
}

/// @dev Parameters for fuzzing the bids
struct FuzzBid {
    uint128 bidAmount;
    uint8 tickNumber;
}
