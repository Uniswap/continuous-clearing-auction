// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// PreBidScenario enum - defines what happens before user's bid
enum PreBidScenario {
    NoBidsBeforeUser, // No bids before user's bid
    BidsBeforeUser, // Bids come before user's bid but not at the users max price
    ClearingPriceBelowMaxPrice, // Bids enter the auction before the user's bid and raise the clearingPrice one tick below maxPrice
    BidsAtClearingPrice, // Bids enter at the users clearingPrice
    __length
}

// PostBidScenario enum - defines what happens after user's bid
enum PostBidScenario {
    NoBidsAfterUser, // User bid is last (current behavior)
    UserAboveClearing, // Bids come after but user stays above clearing
    UserAtClearing, // User ends at clearing price (partial fill)
    UserOutbidLater, // User wins initially but gets outbid later
    UserOutbidImmediately, // User gets outbid in next block
    __length
}

// Exit path classification for verification
enum ExitPath {
    NonGraduated, // Auction didn't graduate - full refund
    FullExit, // Bid above clearing at auction end - fully filled
    PartialExit // Bid outbid mid-auction or at clearing at end - partially filled

}
