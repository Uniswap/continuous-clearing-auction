// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AuctionParameters {
    address currency; // token to raise funds in. Use address(0) for ETH
    address token; // token held by the auction contract to sell
    uint256 totalSupply; // amount of tokens to sell
    address tokensRecipient; // address to receive leftover tokens
    address fundsRecipient; // address to receive all raised funds
    uint256 startBlock; // Block which the first step starts
    uint256 endBlock; // When the auction finishes
    uint256 claimBlock; // Block when the auction can claimed
    uint256 tickSpacing; // Fixed granularity for prices
    address validationHook; // Optional hook called before a bid
    uint256 floorPrice; // Starting floor price for the auction
    // Packed bytes describing token issuance schedule
    bytes auctionStepsData;
}

struct AuctionStep {
    uint256 id; // Incrementing unique id
    uint16 bps; // Basis points to sell per block in the step
    uint256 clearingPrice; // Clearing price at end of step
    uint256 amountFilled; // Amount of tokens sold in the step
    uint256 startBlock; // Start block of the step (inclusive)
    uint256 endBlock; // Ending block of the step (exclusive)
    uint256 next;
}
