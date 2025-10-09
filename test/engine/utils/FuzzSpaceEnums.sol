// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum AuctionParametersSpace {
    TotalSupplySpace,
    FloorPriceSpace,
    TickSpacingSpace,
    ValidationHookSpace,
    TokensRecipientSpace,
    FundsRecipientSpace
}

/// @dev The current time phase of the auction
enum AuctionPhaseSpace {
    // NotYetStarted,
    FirstBlock // first block at which the auction is active
        // Early,
        // Middle,
        // LastBlock,
        // Ended

}

/// @dev The total supply of the auctioned tokens
enum TotalSupplySpace {
    // Low,
    High
}

/// @dev The number of decimals of the auctioned token
enum TokenDecimalsSpace {
    // Low,
    // High,
    Standard // 18 decimals

}

/// @dev The type of currency being raised in the auction
enum CurrencyTypeSpace {
    Native // ETH
        // ERC20

}

/// @dev The number of decimals of the currency token
enum CurrencyDecimalsSpace {
    // Low,
    // High,
    Standard // 18 decimals

}

/// @dev The minimum price of the auctioned token
enum FloorPriceSpace {
    // Zero,
    // OneWei,
    // VeryHigh,
    VeryLow // a very low price as the floor price
        // AtMaxSqrtPrice

}

/// @dev The tick spacing of the auction, adding granularity to the bid prices
enum TickSpacingSpace {
    // Zero,
    // OneWei,
    OneBasisPoint // 1 basis point
        // LessThanFloorPrice,
        // EqualToFloorPrice,
        // BiggerThanFloorPrice,
        // Max

}

/// @dev Is the final price higher then the floor price
enum GraduatedSpace {
    No // the final price is not higher then the floor price
        // Yes

}

/// @dev The amount of current token demand compared to the current supply
enum SubscriptionStatusSpace {
    NotSubscribed // no previous bids
        // SmallSubscription,
        // AlmostSubscribed,
        // ExactlySubscribed,
        // BarelyOversubscribed,
        // MassivelyOversubscribed

}

/// @dev The number of existing bids in the auction
enum ExistingBidsSpace {
    None // no existing bids
        // One,
        // Multiple,
        // Many

}

/// @dev The amount of currency being spent on the bid
enum BidSizeSpace {
    // Zero,
    // OneWei,
    BidMinimum // the minimum amount required to submit a bid
        // Small,
        // Medium,
        // Large,
        // Huge

}

/// @dev The amount a user is willing to pay per token in a bid
enum BidPriceSpace {
    // Zero,
    // OneWei,
    // AtClearingPrice
    OneTickAboveClearing // First legit price to enter the auction
        // ManyTicksAboveClearing,
        // Max

}

/// @dev The amount of auctioned tokens remaining in the auction
enum RemainingSupplySpace {
    // None,
    All // all tokens remaining

}

/// @dev The action being performed by the sender
enum ActionSpace {
    SubmitBid // enter the auction with a bid
        // SubmitBidWithHint,
        // ExitBid,
        // ClaimTokens,
        // Checkpoint

}

/// @dev The rate of emission in the current step of the auctioned tokens
enum EmissionRateSpace {
    // Zero,
    // Small,
    Normal // a generic rate of emission
        // Max

}

/// @dev The duration of emission in the current step of the auctioned tokens
enum EmissionDurationSpace {
    // SingleBlock,
    // Short,
    Normal // a generic duration of emission
        // Long

}

/// @dev The number of emission steps in the auction
enum NumberOfStepsSpace {
    // Zero,
    // Small,
    Normal // a generic number of emission steps
        // Max

}

/// @dev The sender of the bid
enum SenderSpace {
    NewBidder // bidder has not previously submitted a bid
        // RepeatBidder

}

/// @dev The type of validation hook being used in the auction
enum ValidationHookSpace {
    None // no validation hook attached to the auction
        // Reverting,
        // RevertingWithCustomError,
        // OutOfGas,
        // Passing

}

/// @dev The recipient of the auctioned tokens
enum TokensRecipientSpace {
    // None,
    EOA // EOA is the recipient of the auctioned tokens
        // Contract

}

/// @dev The recipient of the raised currency from the auction
enum FundsRecipientSpace {
    // None,
    EOA // EOA is the recipient of the raised currency
        // Contract

}
