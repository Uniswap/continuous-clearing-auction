// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionParameters} from '../../src/Auction.sol';

/// @dev Parameters for fuzzing the auction
struct FuzzDeploymentParams {
    uint256 totalSupply;
    AuctionParameters auctionParams;
    uint8 numberOfSteps;
}

/// @dev Parameters for fuzzing the bids
struct FuzzBid {
    // TODO(md): errors when bumped to uin128
    uint64 bidAmount;
    uint8 tickNumber;
}
