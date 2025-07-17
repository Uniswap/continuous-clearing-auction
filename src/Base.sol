// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AuctionParameters {
    address currency; // token to raise funds in. Use address(0) for ETH
    address token; // token held by the auction contract to sell
    uint256 totalSupply; // amount of tokens to sell
    address tokensRecipient; // address to receive leftover tokens
    address fundsRecipient; // address to receive all raised funds
    uint64 startBlock; // Block which the first step starts
    uint64 endBlock; // When the auction finishes
    uint64 claimBlock; // Block when the auction can claimed
    uint256 tickSpacing; // Fixed granularity for prices
    address validationHook; // Optional hook called before a bid
    uint256 floorPrice; // Starting floor price for the auction
    // Packed bytes describing token issuance schedule
    bytes auctionStepsData;
}
